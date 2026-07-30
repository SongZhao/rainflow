#!/usr/bin/env python3
from __future__ import annotations

import json
import plistlib
import re
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(message)


def check_plist() -> None:
    path = ROOT / "apps/ios/Rainflow/Resources/Info.plist"
    with path.open("rb") as handle:
        data = plistlib.load(handle)
    required = {
        "CFBundleDisplayName",
        "CFBundleIdentifier",
        "CFBundleShortVersionString",
        "CFBundleVersion",
        "NSCameraUsageDescription",
        "NSPhotoLibraryUsageDescription",
        "SUPABASE_URL",
        "SUPABASE_PUBLISHABLE_KEY",
    }
    missing = sorted(required - data.keys())
    if missing:
        fail(f"Info.plist missing keys: {', '.join(missing)}")
    if data.get("CFBundleDisplayName") != "Rainflow":
        fail("Unexpected iPhone display name")
    if data.get("ITSAppUsesNonExemptEncryption") is not False:
        fail("Export-compliance declaration is missing or unexpected")


def check_privacy_manifest() -> None:
    path = ROOT / "apps/ios/Rainflow/Resources/PrivacyInfo.xcprivacy"
    with path.open("rb") as handle:
        data = plistlib.load(handle)
    if data.get("NSPrivacyTracking") is not False:
        fail("Privacy manifest must declare that Rainflow does not track users")

    declared = {
        item.get("NSPrivacyCollectedDataType")
        for item in data.get("NSPrivacyCollectedDataTypes", [])
    }
    required = {
        "NSPrivacyCollectedDataTypeEmailAddress",
        "NSPrivacyCollectedDataTypeUserID",
        "NSPrivacyCollectedDataTypeOtherFinancialInfo",
        "NSPrivacyCollectedDataTypePhotosorVideos",
        "NSPrivacyCollectedDataTypeOtherUserContent",
    }
    missing = sorted(required - declared)
    if missing:
        fail(f"Privacy manifest missing collected data types: {', '.join(missing)}")

    for item in data.get("NSPrivacyCollectedDataTypes", []):
        if item.get("NSPrivacyCollectedDataTypeLinked") is not True:
            fail("Rainflow-collected data must be declared as linked to the signed-in user")
        if item.get("NSPrivacyCollectedDataTypeTracking") is not False:
            fail("Rainflow-collected data must not be declared as tracking")
        purposes = item.get("NSPrivacyCollectedDataTypePurposes", [])
        if "NSPrivacyCollectedDataTypePurposeAppFunctionality" not in purposes:
            fail("Rainflow-collected data must declare app functionality as its purpose")


def check_assets() -> None:
    root = ROOT / "apps/ios/Rainflow/Resources/Assets.xcassets"
    contents_files = list(root.rglob("Contents.json"))
    if not contents_files:
        fail("No asset catalog metadata found")
    for contents in contents_files:
        json.loads(contents.read_text())
    icon = root / "AppIcon.appiconset/AppIcon-1024.png"
    if not icon.exists() or icon.stat().st_size == 0:
        fail("Missing App Store icon")


def check_project_yaml() -> None:
    text = (ROOT / "apps/ios/project.yml").read_text()
    checks = [
        'iOS: "26.0"',
        "exactVersion: 2.53.0",
        "exactVersion: 7.11.1",
        "TARGETED_DEVICE_FAMILY: 1",
        "SWIFT_STRICT_CONCURRENCY: complete",
        "CODE_SIGN_STYLE: Automatic",
    ]
    missing = [item for item in checks if item not in text]
    if missing:
        fail(f"project.yml missing expected settings: {missing}")


def check_local_configuration_is_private() -> None:
    gitignore = (ROOT / ".gitignore").read_text()
    expected = "apps/ios/Config/Local.xcconfig"
    if expected not in gitignore:
        fail("Local.xcconfig is not gitignored")

    # Local.xcconfig is expected to exist on a developer Mac after bootstrap.
    # Release packaging excludes it and verifies that it is absent from the ZIP.
    # Secret scanning remains responsible for rejecting private credentials.


def check_ios_wiring() -> None:
    source_root = ROOT / "apps/ios/Rainflow"
    source = "\n".join(path.read_text() for path in source_root.rglob("*.swift"))
    required = (
        "signInWithOTP",
        "verifyOTP",
        '.rpc("create_transaction"',
        ".upload(",
        "objectKey,",
        "data: fileData",
        "upsert: false",
        "finalizeAttachment",
        "DatabaseMigrator",
        "pending_receipt_uploads",
        "case needsAttention",
        "receiptStatus: ReceiptSaveStatus",
    )
    for token in required:
        if token not in source:
            fail(f"iPhone source is missing expected production wiring: {token}")
    if "path: objectKey" in source or "file: fileData" in source:
        fail("Supabase Storage upload uses obsolete argument labels")
    if ".remove(paths:" in source:
        fail("The app must not delete a receipt after an ambiguous finalization response")


def check_migrations() -> None:
    migration_dir = ROOT / "supabase/migrations"
    migrations = sorted(migration_dir.glob("*.sql"))
    if len(migrations) < 2:
        fail("Expected ledger and receipt-storage migrations")
    joined = "\n".join(path.read_text() for path in migrations).lower()
    required = (
        "create or replace function public.create_transaction",
        "create or replace function public.finalize_attachment",
        "enable row level security",
        "receipt_objects_insert_owner",
        "grant execute on function public.owns_ledger(uuid) to authenticated",
        "accounts_parent_same_ledger_fk",
        "attachment_transaction_same_ledger_fk",
        "new.transaction_id is distinct from old.transaction_id",
        "create constraint trigger postings_balanced_deferred",
        "revoke all on function public.assert_transaction_balanced(uuid) from public",
        "revoke all on function public.touch_updated_at() from public",
        "count(*) filter (where a.id is null)",
        "revoke all on public.ledgers, public.accounts, public.ledger_transactions, public.postings",
        "public.attachment_manifests, public.idempotency_keys from anon, authenticated",
        "revoke all on public.attachment_integrity_events from anon, authenticated",
        "finalized receipt objects are immutable to app clients",
    )
    for token in required:
        if token not in joined:
            fail(f"Migrations missing required safeguard: {token}")

    forbidden_authenticated_writes = re.findall(
        r"grant\s+(?:insert|update|delete|all).*?\s+to\s+authenticated",
        joined,
        flags=re.DOTALL,
    )
    if forbidden_authenticated_writes:
        fail("Authenticated clients must not receive direct table write grants")
    if "filter where" in joined:
        fail("Invalid PostgreSQL FILTER syntax remains in migrations")
    if re.search(r"create\s+policy\s+receipt_objects_(?:update|delete)_owner", joined):
        fail("Authenticated app clients must not overwrite or delete receipt objects")


def check_packaging_ignores() -> None:
    gitignore = (ROOT / ".gitignore").read_text().splitlines()
    required = {"build/", "*.xcarchive/", "*.ipa", ".swiftpm/"}
    missing = sorted(required - set(gitignore))
    if missing:
        fail(f".gitignore missing generated release output: {', '.join(missing)}")


def check_markdown_links() -> None:
    link_pattern = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
    broken: list[str] = []
    for document in sorted(ROOT.rglob("*.md")):
        if any(part in {"node_modules", ".next", ".build"} for part in document.parts):
            continue
        for raw_target in link_pattern.findall(document.read_text()):
            target = raw_target.strip().split()[0].strip("<>")
            if not target or target.startswith(("#", "http://", "https://", "mailto:", "sandbox:")):
                continue
            target = unquote(target.split("#", 1)[0].split("?", 1)[0])
            resolved = (document.parent / target).resolve()
            try:
                resolved.relative_to(ROOT.resolve())
            except ValueError:
                broken.append(f"{document.relative_to(ROOT)} -> {raw_target} (outside repository)")
                continue
            if not resolved.exists():
                broken.append(f"{document.relative_to(ROOT)} -> {raw_target}")
    if broken:
        fail("Broken Markdown links:\n" + "\n".join(broken))


def check_document_truthfulness() -> None:
    combined = "\n".join(
        path.read_text()
        for path in [
            ROOT / "README.md",
            ROOT / "apps/ios/README.md",
            ROOT / "docs/IMPLEMENTATION_STATUS.md",
            ROOT / "supabase/README.md",
        ]
    )
    stale_claims = (
        "iPhone transaction saving is simulated",
        "The app currently uses preview/mock data",
        "GRDB cache, authenticated API adapters, receipt finalization, OTP",
    )
    for claim in stale_claims:
        if claim in combined:
            fail(f"Stale implementation claim remains: {claim}")
    if "does not independently hash" not in combined:
        fail("Attachment checksum limitation must be documented explicitly")


def main() -> None:
    check_plist()
    check_privacy_manifest()
    check_assets()
    check_project_yaml()
    check_local_configuration_is_private()
    check_ios_wiring()
    check_migrations()
    check_packaging_ignores()
    check_markdown_links()
    check_document_truthfulness()
    print("Project metadata, links, source wiring, and SQL safeguards validated.")


if __name__ == "__main__":
    main()

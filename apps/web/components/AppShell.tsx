"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  BarChart3,
  Bell,
  Camera,
  ChevronDown,
  FileImage,
  FolderClock,
  Gauge,
  Landmark,
  LogOut,
  Menu,
  Plus,
  Settings,
  WalletCards,
} from "lucide-react";
import { FormEvent, useState } from "react";
import { CaptureDialog } from "./CaptureDialog";
import { useLedger } from "./LedgerProvider";

const navigation = [
  { href: "/dashboard", label: "Dashboard", icon: Gauge },
  { href: "/accounts", label: "Accounts", icon: Landmark },
  { href: "/reports", label: "Reports", icon: BarChart3 },
  { href: "/attachments", label: "Attachments", icon: FileImage },
];

const secondary = [
  { label: "Recurring", icon: FolderClock },
  { label: "Budget", icon: WalletCards, badge: "Later" },
  { label: "Settings", icon: Settings },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const {
    phase,
    user,
    errorMessage,
    isWorking,
    sendCode,
    verifyCode,
    signOut,
    createLedger,
    switchLedger,
    inviteLedgerMember,
    ledger,
    ledgers
  } = useLedger();
  const pathname = usePathname();
  const [captureOpen, setCaptureOpen] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [ledgerMenuOpen, setLedgerMenuOpen] = useState(false);
  const [createLedgerOpen, setCreateLedgerOpen] = useState(false);
  const [inviteOpen, setInviteOpen] = useState(false);

  if (phase !== "ready") {
    return (
      <AuthScreen
        phase={phase}
        errorMessage={errorMessage}
        isWorking={isWorking}
        onSendCode={sendCode}
        onVerifyCode={verifyCode}
        onCreateLedger={createLedger}
      />
    );
  }

  return (
    <div className="app-shell">
      <aside className={`sidebar ${sidebarOpen ? "sidebar-open" : ""}`}>
        <div className="brand-lockup">
          <span className="brand-drop">◆</span>
          <span>Rainflow</span>
        </div>

        <nav className="nav-list" aria-label="Primary navigation">
          {navigation.map(({ href, label, icon: Icon }) => (
            <Link
              key={href}
              href={href}
              className={`nav-link ${pathname === href ? "active" : ""}`}
              onClick={() => setSidebarOpen(false)}
            >
              <Icon size={18} />
              <span>{label}</span>
            </Link>
          ))}
        </nav>

        <div className="nav-divider" />
        <nav className="nav-list" aria-label="Secondary navigation">
          {secondary.map(({ label, icon: Icon, badge }) => (
            <button className="nav-link nav-button" key={label} type="button">
              <Icon size={18} />
              <span>{label}</span>
              {badge ? <span className="nav-badge">{badge}</span> : null}
            </button>
          ))}
        </nav>

        <div className="sidebar-user">
          <div className="avatar">{initials(user?.email)}</div>
          <div>
            <strong>{user?.email?.split("@")[0] ?? "Rainflow User"}</strong>
            <span>{user?.email ?? "Signed in"}</span>
          </div>
          <button className="logout-button" type="button" onClick={() => void signOut()} aria-label="Sign out">
            <LogOut size={17} aria-hidden="true" />
          </button>
        </div>
      </aside>

      <main className="main-area">
        <header className="topbar">
          <button className="icon-button mobile-menu" type="button" onClick={() => setSidebarOpen((value) => !value)} aria-label="Toggle navigation">
            <Menu size={20} />
          </button>
          <div className="ledger-menu-wrap">
            <button className="ledger-switcher" type="button" onClick={() => setLedgerMenuOpen((value) => !value)}>
              {ledger?.name ?? "Personal Ledger"}
              <ChevronDown size={15} />
            </button>
            {ledgerMenuOpen ? (
              <div className="ledger-menu">
                {ledgers.map((item) => (
                  <button
                    className={item.id === ledger?.id ? "ledger-menu-item active" : "ledger-menu-item"}
                    type="button"
                    key={item.id}
                    onClick={() => {
                      setLedgerMenuOpen(false);
                      void switchLedger(item.id);
                    }}
                  >
                    <span><strong>{item.name}</strong><small>{item.kind === "shared" ? "Shared" : "Personal"} · {item.role}</small></span>
                  </button>
                ))}
                <div className="ledger-menu-divider" />
                <button className="ledger-menu-item" type="button" onClick={() => {
                  setLedgerMenuOpen(false);
                  setCreateLedgerOpen(true);
                }}>
                  <span><strong>Create ledger</strong><small>Personal or shared</small></span>
                </button>
              </div>
            ) : null}
          </div>
          <div className="topbar-actions">
            {ledger?.kind === "shared" && ledger.role !== "member" ? (
              <button className="secondary-button" type="button" onClick={() => setInviteOpen(true)}>
                Invite
              </button>
            ) : null}
            <button className="icon-button" type="button" aria-label="Notifications">
              <Bell size={19} />
            </button>
            <button className="primary-button" type="button" onClick={() => setCaptureOpen(true)}>
              <Plus size={18} />
              Add transaction
            </button>
          </div>
        </header>
        <div className="content-area">{children}</div>
      </main>

      <button className="floating-capture" type="button" onClick={() => setCaptureOpen(true)} aria-label="Capture receipt or add transaction">
        <Camera size={24} />
      </button>

      <CaptureDialog open={captureOpen} onClose={() => setCaptureOpen(false)} />
      <CreateLedgerDialog
        open={createLedgerOpen}
        isWorking={isWorking}
        onClose={() => setCreateLedgerOpen(false)}
        onCreate={async (input) => {
          await createLedger(input);
          setCreateLedgerOpen(false);
        }}
      />
      <InviteLedgerDialog
        open={inviteOpen}
        isWorking={isWorking}
        onClose={() => setInviteOpen(false)}
        onInvite={async (email, role) => {
          await inviteLedgerMember(email, role);
          setInviteOpen(false);
        }}
      />
    </div>
  );
}

function CreateLedgerDialog({
  open,
  isWorking,
  onClose,
  onCreate
}: {
  open: boolean;
  isWorking: boolean;
  onClose: () => void;
  onCreate: (input: { name: string; currencyCode: string; kind: "personal" | "shared" }) => Promise<void>;
}) {
  const [name, setName] = useState("Personal");
  const [currencyCode, setCurrencyCode] = useState("USD");
  const [kind, setKind] = useState<"personal" | "shared">("personal");
  const [localError, setLocalError] = useState<string | null>(null);

  if (!open) return null;

  async function submit(event: FormEvent) {
    event.preventDefault();
    setLocalError(null);
    try {
      await onCreate({ name: name.trim() || (kind === "shared" ? "Shared Ledger" : "Personal"), currencyCode, kind });
    } catch (error) {
      setLocalError(error instanceof Error ? error.message : "Could not create ledger.");
    }
  }

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="create-ledger-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-header">
          <div><span className="eyebrow">Ledger</span><h2 id="create-ledger-title">Create ledger</h2></div>
          <button className="icon-button" type="button" onClick={onClose} aria-label="Close">×</button>
        </div>
        <form className="transaction-form" onSubmit={submit}>
          <div className="segmented-control" aria-label="Ledger type">
            <button type="button" className={kind === "personal" ? "active" : ""} onClick={() => setKind("personal")}>Personal</button>
            <button type="button" className={kind === "shared" ? "active" : ""} onClick={() => setKind("shared")}>Shared</button>
          </div>
          <div className="form-grid">
            <label className="field field-wide">
              <span>Ledger name</span>
              <input value={name} onChange={(event) => setName(event.target.value)} placeholder={kind === "shared" ? "Household" : "Personal"} autoFocus />
            </label>
            <label className="field">
              <span>Currency</span>
              <select value={currencyCode} onChange={(event) => setCurrencyCode(event.target.value)}>
                {["USD", "CAD", "EUR", "GBP", "JPY", "AUD"].map((item) => <option value={item} key={item}>{item}</option>)}
              </select>
            </label>
          </div>
          {localError ? <p className="auth-error">{localError}</p> : null}
          <div className="dialog-actions">
            <button className="secondary-button" type="button" onClick={onClose}>Cancel</button>
            <button className="primary-button" type="submit" disabled={isWorking}>{isWorking ? "Creating..." : "Create ledger"}</button>
          </div>
        </form>
      </section>
    </div>
  );
}

function InviteLedgerDialog({
  open,
  isWorking,
  onClose,
  onInvite
}: {
  open: boolean;
  isWorking: boolean;
  onClose: () => void;
  onInvite: (email: string, role: "admin" | "member") => Promise<void>;
}) {
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<"admin" | "member">("member");
  const [localError, setLocalError] = useState<string | null>(null);

  if (!open) return null;

  async function submit(event: FormEvent) {
    event.preventDefault();
    setLocalError(null);
    try {
      await onInvite(email.trim(), role);
      setEmail("");
    } catch (error) {
      setLocalError(error instanceof Error ? error.message : "Could not invite user.");
    }
  }

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="invite-ledger-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-header">
          <div><span className="eyebrow">Shared ledger</span><h2 id="invite-ledger-title">Invite user</h2></div>
          <button className="icon-button" type="button" onClick={onClose} aria-label="Close">×</button>
        </div>
        <form className="transaction-form" onSubmit={submit}>
          <div className="form-grid">
            <label className="field field-wide">
              <span>User email</span>
              <input value={email} onChange={(event) => setEmail(event.target.value)} placeholder="person@example.com" type="email" autoFocus />
            </label>
            <label className="field">
              <span>Role</span>
              <select value={role} onChange={(event) => setRole(event.target.value as "admin" | "member")}>
                <option value="member">Member</option>
                <option value="admin">Admin</option>
              </select>
            </label>
          </div>
          <p className="form-note">The invited person gets access after signing in with this exact email.</p>
          {localError ? <p className="auth-error">{localError}</p> : null}
          <div className="dialog-actions">
            <button className="secondary-button" type="button" onClick={onClose}>Cancel</button>
            <button className="primary-button" type="submit" disabled={isWorking || !email.includes("@")}>{isWorking ? "Inviting..." : "Invite"}</button>
          </div>
        </form>
      </section>
    </div>
  );
}

function AuthScreen({
  phase,
  errorMessage,
  isWorking,
  onSendCode,
  onVerifyCode,
  onCreateLedger
}: {
  phase: string;
  errorMessage: string | null;
  isWorking: boolean;
  onSendCode: (email: string) => Promise<void>;
  onVerifyCode: (email: string, token: string) => Promise<void>;
  onCreateLedger: () => Promise<void>;
}) {
  const [email, setEmail] = useState("");
  const [token, setToken] = useState("");
  const [codeSent, setCodeSent] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);

  async function send(event: FormEvent) {
    event.preventDefault();
    setLocalError(null);
    try {
      await onSendCode(email.trim());
      setCodeSent(true);
    } catch (error) {
      setLocalError(error instanceof Error ? error.message : "Could not send code.");
    }
  }

  async function verify(event: FormEvent) {
    event.preventDefault();
    setLocalError(null);
    try {
      await onVerifyCode(email.trim(), token.trim());
    } catch (error) {
      setLocalError(error instanceof Error ? error.message : "Could not verify code.");
    }
  }

  return (
    <main className="auth-page">
      <section className="auth-card">
        <span className="brand-drop auth-drop">◆</span>
        <h1>Welcome to Rainflow</h1>
        {phase === "checking" ? <p>Checking your session...</p> : null}
        {phase === "configurationRequired" ? <p>Add the web Supabase settings to <code>apps/web/.env.local</code>.</p> : null}
        {phase === "failed" ? <p>Rainflow could not load. Try refreshing after checking Supabase.</p> : null}
        {phase === "needsLedger" ? (
          <>
            <p>Your account is signed in, but no ledger exists yet.</p>
            <button className="primary-button" type="button" disabled={isWorking} onClick={() => void onCreateLedger()}>
              Create personal ledger
            </button>
          </>
        ) : null}
        {phase === "signedOut" ? (
          codeSent ? (
            <form className="auth-form" onSubmit={verify}>
              <p>Enter the sign-in code from your email.</p>
              <input value={token} onChange={(event) => setToken(event.target.value.replace(/\D/g, "").slice(0, 8))} placeholder="00000000" inputMode="numeric" autoFocus />
              <button className="primary-button" type="submit" disabled={isWorking || token.length < 6}>Verify code</button>
              <button className="secondary-button" type="button" disabled={isWorking} onClick={() => setCodeSent(false)}>Use another email</button>
            </form>
          ) : (
            <form className="auth-form" onSubmit={send}>
              <p>Enter your email and Rainflow will send a sign-in code.</p>
              <input value={email} onChange={(event) => setEmail(event.target.value)} placeholder="you@example.com" type="email" autoFocus />
              <button className="primary-button" type="submit" disabled={isWorking || !email.includes("@")}>Send code</button>
            </form>
          )
        ) : null}
        {localError || errorMessage ? <p className="auth-error">{localError ?? errorMessage}</p> : null}
      </section>
    </main>
  );
}

function initials(email?: string) {
  if (!email) return "RF";
  return email.slice(0, 2).toUpperCase();
}

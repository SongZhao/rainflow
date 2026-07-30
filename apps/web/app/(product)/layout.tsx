import { AppShell } from "@/components/AppShell";
import { LedgerProvider } from "@/components/LedgerProvider";

export default function ProductLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <LedgerProvider>
      <AppShell>{children}</AppShell>
    </LedgerProvider>
  );
}

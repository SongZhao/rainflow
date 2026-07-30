"use client";

import Link from "next/link";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useLedger } from "@/components/LedgerProvider";

export default function TransactionsPage() {
  const router = useRouter();
  const { ledger } = useLedger();

  useEffect(() => {
    router.replace(ledger ? `/ledgers/${ledger.id}` : "/accounts");
  }, [ledger, router]);

  return (
    <div className="page-stack">
      <section className="card detail-card">
        <div className="empty-state">
          <h3>Transactions live inside ledgers and accounts</h3>
          <p>Rainflow is opening the current ledger.</p>
          <Link className="primary-button" href={ledger ? `/ledgers/${ledger.id}` : "/accounts"}>Open ledger</Link>
        </div>
      </section>
    </div>
  );
}

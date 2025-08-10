"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { getFilteredRowModel, getSortedRowModel } from "@tanstack/react-table";
import { Circle, Info } from "lucide-react";
import { useParams, useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { z } from "zod";
import DividendStatusIndicator from "@/app/(dashboard)/equity/DividendStatusIndicator";
import { DashboardHeader } from "@/components/DashboardHeader";
import DataTable, { createColumnHelper, useTable } from "@/components/DataTable";
import MutationButton from "@/components/MutationButton";
import TableSkeleton from "@/components/TableSkeleton";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Separator } from "@/components/ui/separator";
import { useCurrentCompany } from "@/global";
import type { RouterOutput } from "@/trpc";
import { trpc } from "@/trpc/client";
import { formatMoney } from "@/utils/formatMoney";
import { request } from "@/utils/request";
import { approve_company_dividend_computation_path, company_dividend_computation_path } from "@/utils/routes";
import { formatDate } from "@/utils/time";

export default function DividendRoundPage() {
  const { id, type } = useParams<{ id: string; type: "draft" | "round" }>();
  const isDraft = type === "draft";

  return (
    <>
      <DashboardHeader title="Dividend" />
      {isDraft ? <DividendComputation id={id} /> : <DividendRound id={id} />}
    </>
  );
}

type Dividend = RouterOutput["dividends"]["list"][number];
const DividendRound = ({ id }: { id: string }) => {
  const company = useCurrentCompany();
  const router = useRouter();

  const { data: dividends = [], isLoading } = trpc.dividends.list.useQuery({
    companyId: company.id,
    dividendRoundId: Number(id),
  });

  const columnHelper = createColumnHelper<Dividend>();
  const columns = useMemo(
    () => [
      columnHelper.accessor("investor.user.name", {
        id: "investor",
        header: "Investor",
        cell: (info) => <div className="font-light">{info.getValue() || "Unknown"}</div>,
        footer: "Total",
      }),
      columnHelper.accessor("numberOfShares", {
        header: "Number of shares",
        cell: (info) => {
          const shares = info.getValue();
          return shares && shares > 0 ? Number(shares).toLocaleString() : "—";
        },
        meta: { numeric: true },
        footer: () => {
          const sum = dividends.reduce(
            (sum, dividend) => sum + (dividend.numberOfShares ? Number(dividend.numberOfShares) : 0),
            0,
          );
          return sum > 0 ? sum.toLocaleString() : "—";
        },
      }),
      columnHelper.accessor("totalAmountInCents", {
        header: "Return amount",
        cell: (info) => formatMoney(Number(info.getValue()) / 100),
        meta: { numeric: true },
        footer: formatMoney(dividends.reduce((sum, dividend) => sum + Number(dividend.totalAmountInCents) / 100, 0)),
      }),
      columnHelper.accessor("totalAmountInCents", {
        id: "flexileFee",
        header: "Fees",
        cell: (info) => formatMoney(calculateFlexileFees(Number(info.getValue()) / 100)),
        meta: { numeric: true },
        footer: formatMoney(
          dividends.reduce((sum, dividend) => sum + calculateFlexileFees(Number(dividend.totalAmountInCents) / 100), 0),
        ),
      }),
      columnHelper.accessor("status", {
        header: "Status",
        cell: (info) => <DividendStatusIndicator dividend={info.row.original} />,
        meta: {
          filterOptions: Array.from(new Set(dividends.map((dividend) => dividend.status))),
        },
      }),
    ],
    [dividends],
  );

  const table = useTable({
    data: dividends,
    columns,
    getFilteredRowModel: getFilteredRowModel(),
    getSortedRowModel: getSortedRowModel(),
    initialState: {
      sorting: [
        {
          id: "totalAmountInCents",
          desc: true,
        },
      ],
    },
  });

  const onRowClicked = (row: Dividend) => {
    if (row.investor?.user?.id) {
      router.push(`/people/${row.investor.user.id}?tab=dividends`);
    }
  };

  if (isLoading) {
    return <TableSkeleton columns={5} />;
  }

  return <DataTable table={table} onRowClicked={onRowClicked} searchColumn="investor" />;
};

const dividendComputationSchema = z.object({
  id: z.number(),
  total_amount_in_usd: z.string(),
  dividends_issuance_date: z.string(),
  return_of_capital: z.boolean(),
  number_of_shareholders: z.number(),
  investor_breakdown: z.array(
    z.object({
      investor_name: z.string(),
      company_investor_id: z.number().nullable(),
      investor_external_id: z.string().nullable(),
      total_amount: z.string(),
      number_of_shares: z.number(),
    }),
  ),
});

type DividendComputation = z.infer<typeof dividendComputationSchema>;
type DividendComputationOutput = DividendComputation["investor_breakdown"][number];
const DividendComputation = ({ id }: { id: string }) => {
  const company = useCurrentCompany();
  const router = useRouter();
  const [isModalOpen, setIsModalOpen] = useState(false);

  const { data: dividendComputation, isLoading } = useQuery({
    queryKey: ["dividend-computation", id],
    queryFn: async () => {
      const response = await request({
        method: "GET",
        accept: "json",
        url: company_dividend_computation_path(company.id, BigInt(id)),
        assertOk: true,
      });
      return dividendComputationSchema.parse(await response.json());
    },
  });

  const dividendOutputs = dividendComputation?.investor_breakdown || [];

  const columnHelper = createColumnHelper<DividendComputationOutput>();
  const columns = useMemo(
    () => [
      columnHelper.accessor("investor_name", {
        id: "investor",
        header: "Investor",
        cell: (info) => <div className="font-light">{info.getValue() || "Unknown"}</div>,
        footer: "Total",
      }),
      columnHelper.accessor("number_of_shares", {
        header: "Number of shares",
        cell: (info) => info.getValue().toLocaleString(),
        meta: { numeric: true },
        footer: dividendOutputs.reduce((sum, output) => sum + output.number_of_shares, 0).toLocaleString(),
      }),
      columnHelper.accessor("total_amount", {
        header: "Return amount",
        cell: (info) => formatMoney(Number(info.getValue())),
        meta: { numeric: true },
        footer: formatMoney(dividendOutputs.reduce((sum, output) => sum + Number(output.total_amount), 0)),
      }),
      columnHelper.accessor("total_amount", {
        id: "flexileFee",
        header: "Fees",
        cell: (info) => formatMoney(calculateFlexileFees(Number(info.getValue()))),
        meta: { numeric: true },
        footer: formatMoney(
          dividendOutputs.reduce((sum, output) => sum + calculateFlexileFees(Number(output.total_amount)), 0),
        ),
      }),
      columnHelper.accessor("investor_external_id", {
        id: "status",
        header: "Status",
        cell: () => (
          <div className="flex items-center gap-2">
            <Circle className="size-4 text-black/18" />
            <span>Draft</span>
          </div>
        ),
      }),
    ],
    [dividendOutputs],
  );

  const table = useTable({
    data: dividendOutputs,
    columns,
    getFilteredRowModel: getFilteredRowModel(),
    getSortedRowModel: getSortedRowModel(),
    initialState: {
      sorting: [
        {
          id: "total_amount",
          desc: true,
        },
      ],
    },
  });

  const onRowClicked = (row: DividendComputationOutput) => {
    if (row.investor_external_id) {
      router.push(`/people/${row.investor_external_id}?tab=dividends`);
    }
  };

  if (isLoading || !dividendComputation) {
    return <TableSkeleton columns={5} />;
  }

  return (
    <>
      <DistributionDraftNotice />

      <DataTable
        table={table}
        onRowClicked={onRowClicked}
        searchColumn="investor"
        actions={
          <ApproveDistributionModal open={isModalOpen} onOpenChange={setIsModalOpen} data={dividendComputation} />
        }
      />
    </>
  );
};

const DistributionDraftNotice = () => (
  <div className="mb-4 flex items-center gap-2 bg-blue-50 px-4 py-4">
    <Info className="size-3.5 flex-shrink-0 text-blue-600" />
    <p className="text-sm">
      <strong>Dividend distribution is still a draft.</strong> Shareholders won't be notified or paid until you click{" "}
      <strong>Finalize distribution.</strong>
    </p>
  </div>
);

export const ApproveDistributionModal = ({
  open,
  onOpenChange,
  data,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  data: DividendComputation;
}) => {
  const [isConfirmed, setIsConfirmed] = useState(false);
  const company = useCurrentCompany();
  const router = useRouter();

  const approveMutation = useMutation({
    mutationFn: async () => {
      const response = await request({
        method: "POST",
        accept: "json",
        url: approve_company_dividend_computation_path(company.id, BigInt(data.id)),
        assertOk: true,
      });
      return response.json();
    },
    onSuccess: (result) => {
      onOpenChange(false);
      // Redirect to the dividend round page
      router.push(`/equity/dividend_rounds/round/${result.id}`);
    },
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogTrigger asChild>
        <Button variant="default" size="small">
          Approve distribution
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Distribution details</DialogTitle>
          <DialogDescription>
            Please confirm all details are accurate. After confirmation, shareholders will be notified, payments
            scheduled, and funds pulled from your connected account.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-2">
          <div className="flex justify-between">
            <span>Distribution type:</span>
            <span>{data.return_of_capital ? "Return of capital" : "Dividends"}</span>
          </div>

          <Separator />

          <div className="flex justify-between">
            <span>Payment date:</span>
            <span>{formatDate(data.dividends_issuance_date)}</span>
          </div>

          <Separator />

          <div className="flex justify-between">
            <span>Shareholders:</span>
            <span>{data.number_of_shareholders}</span>
          </div>

          <Separator />

          <div className="flex justify-between">
            <span>Distribution amount:</span>
            <span>{formatMoney(data.total_amount_in_usd)}</span>
          </div>

          <Separator />

          <div className="flex justify-between">
            <div>
              <div>Processing fees:</div>
              <div className="mt-1 text-sm text-gray-500">$0.50 + 1.5%, up to $15/investor</div>
            </div>
            <span>
              {/* TODO(naz) */}
              {formatMoney(Math.min(0.5 + Number(data.total_amount_in_usd) * 0.015, 15) * data.number_of_shareholders)}
            </span>
          </div>

          <Separator />

          <div className="flex justify-between font-medium">
            <span>Total cost:</span>
            <span>
              {formatMoney(
                Number(data.total_amount_in_usd) +
                  Math.min(0.5 + Number(data.total_amount_in_usd) * 0.015, 15) * data.number_of_shareholders,
              )}
            </span>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Checkbox
            checked={isConfirmed}
            onCheckedChange={(checked) => setIsConfirmed(checked === true)}
            label="I've reviewed all information and confirm it's correct."
          />
        </div>
        <DialogFooter>
          <MutationButton
            mutation={approveMutation}
            disabled={!isConfirmed}
            loadingText="Approving..."
            errorText={approveMutation.error?.message || "Something went wrong. Please try again."}
          >
            Approve distribution
          </MutationButton>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

function calculateFlexileFees(totalAmountInUsd: number): number {
  const FLEXILE_FEE_RATE = 0.029; // 2.9%
  const FLEXILE_FLAT_FEE = 0.3; // $0.30
  const FLEXILE_MAX_FEE = 30; // $30 cap

  const calculatedFee = totalAmountInUsd * FLEXILE_FEE_RATE + FLEXILE_FLAT_FEE;
  return Math.min(FLEXILE_MAX_FEE, calculatedFee);
}

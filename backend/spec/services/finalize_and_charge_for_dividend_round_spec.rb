# frozen_string_literal: true

RSpec.describe FinalizeAndChargeForDividendRound do
  let(:company) { create(:company) }
  let(:company_investor) { create(:company_investor, company: company) }
  let(:dividend_computation) { create(:dividend_computation, company: company, total_amount_in_usd: 1000) }
  let!(:dividend_computation_output) do
    create(:dividend_computation_output,
           dividend_computation: dividend_computation,
           company_investor: company_investor,
           total_amount_in_usd: 1000)
  end
  let(:service) { described_class.new(dividend_computation: dividend_computation) }

  describe "#perform" do
    subject(:perform) { service.perform }

    context "when everything succeeds" do
      before do
        setup_intent = double(
          payment_method: "pm_test",
          customer: "cus_test"
        )
        allow_any_instance_of(CompanyStripeAccount).to receive(:stripe_setup_intent).and_return(setup_intent)

        payment_intent = double(
          id: "pi_test",
          latest_charge: double(id: "ch_test", amount: 100000)
        )
        allow(Stripe::PaymentIntent).to receive(:create).and_return(payment_intent)
      end

      it "successfully creates dividend round, consolidated invoice, charges it, and finalizes" do
        expect { perform }.to change(DividendRound, :count).by(1)
          .and change(ConsolidatedInvoice, :count).by(1)
          .and change(Dividend, :count).by(1)

        dividend_round = DividendRound.last
        expect(dividend_round.company).to eq(company)
        expect(dividend_round.status).to eq("Issued")
        expect(dividend_round.total_amount_in_cents).to eq(100000)

        consolidated_invoice = ConsolidatedInvoice.last
        expect(consolidated_invoice.company).to eq(company)
        expect(dividend_round.consolidated_invoice).to eq(consolidated_invoice)
        expect(consolidated_invoice.status).to eq(ConsolidatedInvoice::SENT)
        expect(consolidated_invoice.invoice_amount_cents).to eq(100000)

        dividend_computation.reload
        expect(dividend_computation).to be_finalized
        expect(dividend_computation.dividend_round).to eq(dividend_round)

        dividend = Dividend.last
        expect(dividend.company_investor).to eq(company_investor)
        expect(dividend.dividend_round).to eq(dividend_round)
        expect(dividend.total_amount_in_cents).to eq(100000)
      end
    end

    context "when consolidated invoice creation fails" do
      before do
        # Make the company invalid to cause invoice creation to fail
        company.update_column(:deactivated_at, Time.current)
      end

      it "rolls back, raises error and does not finalize dividend computation" do
        expect { perform }.to raise_error("Company must be active")
          .and change(DividendRound, :count).by(0)
          .and change(ConsolidatedInvoice, :count).by(0)
          .and change(Dividend, :count).by(0)

        dividend_computation.reload
        expect(dividend_computation).not_to be_finalized
        expect(dividend_computation.dividend_round).to be_nil
      end
    end

    context "when charging the consolidated invoice fails" do
      before do
        setup_intent = double(
          payment_method: "pm_test",
          customer: "cus_test"
        )
        allow_any_instance_of(CompanyStripeAccount).to receive(:stripe_setup_intent).and_return(setup_intent)

        allow(Stripe::PaymentIntent).to receive(:create).and_raise(Stripe::StripeError.new("Card declined"))
      end

      it "rolls back, raises error and does not finalize dividend computation" do
        expect { perform }.to raise_error(Stripe::StripeError)
          .and change(DividendRound, :count).by(0)
          .and change(ConsolidatedInvoice, :count).by(0)
          .and change(Dividend, :count).by(0)

        dividend_computation.reload
        expect(dividend_computation).not_to be_finalized
        expect(dividend_computation.dividend_round).to be_nil
      end
    end
  end
end

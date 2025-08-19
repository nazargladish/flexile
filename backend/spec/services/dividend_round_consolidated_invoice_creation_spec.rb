# frozen_string_literal: true

RSpec.describe DividendRoundConsolidatedInvoiceCreation do
  let(:company) { create(:company) }

  describe "#process" do
    subject(:process) { described_class.new(dividend_round).process }

    shared_examples "raises validation error" do |error_message|
      it "raises #{error_message}" do
        expect { process }.to raise_error(error_message)
      end
    end

    shared_examples "raises record invalid error" do |error_pattern|
      it "raises ActiveRecord::RecordInvalid with specific message" do
        expect { process }.to raise_error(ActiveRecord::RecordInvalid, error_pattern)
      end
    end

    context "with invalid prerequisites" do
      context "when company is inactive" do
        let(:inactive_company) { create(:company, deactivated_at: Time.current) }
        let(:dividend_round) { create(:dividend_round, company: inactive_company, status: "Issued") }

        include_examples "raises validation error", "Company must be active"
      end

      context "when company bank account is not ready" do
        let(:company_without_ready_bank) { create(:company, :without_bank_account) }
        let(:dividend_round) { create(:dividend_round, company: company_without_ready_bank, status: "Issued") }

        before do
          create(:company_stripe_account, :initial, company: company_without_ready_bank)
        end

        include_examples "raises validation error", "Company must have bank account ready"
      end

      context "when dividend round is not in issued status" do
        let(:dividend_round) { create(:dividend_round, company: company, status: "Paid") }

        include_examples "raises validation error", "Dividend round must be in issued status"
      end

      context "when dividend round already has a consolidated invoice" do
        let(:dividend_round) { create(:dividend_round, company: company, status: "Issued") }
        let(:existing_invoice) { create(:consolidated_invoice, company: company) }

        before do
          dividend_round.update!(consolidated_invoice: existing_invoice)
        end

        include_examples "raises record invalid error", /cannot be changed once set/
      end
    end

    context "with valid dividend round" do
      let(:dividend_round) { create(:dividend_round, company: company, status: "Issued", total_amount_in_cents: 75000) }

      context "with dividends" do
        let!(:dividends) { create_list(:dividend, 3, dividend_round: dividend_round, total_amount_in_cents: 25000) }
        let(:expected_flexile_fee) do
          dividends.sum { |dividend| FlexileFeeCalculator.calculate_dividend_fee_cents(dividend.total_amount_in_cents) }
        end

        it "creates a consolidated invoice for the dividend round" do
          expect { process }.to change(ConsolidatedInvoice, :count).by(1)
          consolidated_invoice = ConsolidatedInvoice.last
          expect(consolidated_invoice.company).to eq(company)
          expect(consolidated_invoice.status).to eq(ConsolidatedInvoice::SENT)
          expect(consolidated_invoice.invoice_date).to eq(Date.current)
          expect(consolidated_invoice.period_start_date).to eq(dividend_round.issued_at.to_date)
          expect(consolidated_invoice.period_end_date).to eq(dividend_round.issued_at.to_date)
          expect(consolidated_invoice.invoice_amount_cents).to eq(dividend_round.total_amount_in_cents)
          expect(consolidated_invoice.flexile_fee_cents).to eq(expected_flexile_fee)
          expect(consolidated_invoice.transfer_fee_cents).to eq(0)
        end

        it "calculates total correctly" do
          consolidated_invoice = process
          expect(consolidated_invoice.total_cents).to eq(
            consolidated_invoice.invoice_amount_cents +
            consolidated_invoice.flexile_fee_cents +
            consolidated_invoice.transfer_fee_cents
          )
        end

        it "associates the consolidated invoice with the dividend round" do
          consolidated_invoice = process
          expect(dividend_round.reload.consolidated_invoice).to eq(consolidated_invoice)
        end

        it "generates correct invoice number" do
          create_list(:consolidated_invoice, 2, company: company)
          consolidated_invoice = process
          expect(consolidated_invoice.invoice_number).to eq("FX-3")
        end

        it "handles dividend round issued in the past" do
          past_date = 1.week.ago
          dividend_round.update!(issued_at: past_date)
          consolidated_invoice = process
          expect(consolidated_invoice.period_start_date).to eq(past_date.to_date)
          expect(consolidated_invoice.period_end_date).to eq(past_date.to_date)
          expect(consolidated_invoice.invoice_date).to eq(Date.current)
        end
      end

      # Should be removed
      context "without dividends" do
        let(:dividend_round) { create(:dividend_round, company: company, status: "Issued", total_amount_in_cents: 0) }

        it "still creates a valid consolidated invoice" do
          expect { process }.to change(ConsolidatedInvoice, :count).by(1)
          consolidated_invoice = ConsolidatedInvoice.last
          expect(consolidated_invoice).to be_persisted
          expect(consolidated_invoice.company).to eq(company)
          expect(consolidated_invoice.status).to eq(ConsolidatedInvoice::SENT)
          expect(consolidated_invoice.invoice_date).to eq(Date.current)
          expect(consolidated_invoice.period_start_date).to eq(dividend_round.issued_at.to_date)
          expect(consolidated_invoice.period_end_date).to eq(dividend_round.issued_at.to_date)
          # Would fail and  ActiveRecord::RecordInvalid: Validation failed: Total amount in cents must be greater than 0
          expect(consolidated_invoice.invoice_amount_cents).to eq(0)
          expect(consolidated_invoice.flexile_fee_cents).to eq(0)
          expect(consolidated_invoice.transfer_fee_cents).to eq(0)
        end
      end
    end
  end
end

# frozen_string_literal: true

class DividendRoundConsolidatedInvoiceCreation
  attr_reader :dividend_round

  def initialize(dividend_round)
    @dividend_round = dividend_round
  end

  def process
    raise "Company must be active" unless company.active?
    raise "Company must have bank account ready" unless company.bank_account_ready?
    raise "Dividend round must be in issued status" unless dividend_round.status == "Issued"

    consolidated_invoice = company.consolidated_invoices.build(
      invoice_date: Date.current,
      invoice_number: "FX-#{company.consolidated_invoices.count + 1}",
      status: ConsolidatedInvoice::SENT
    )

    flexile_fee_cents = dividend_round.dividends.sum do |dividend|
      FlexileFeeCalculator.calculate_dividend_fee_cents(dividend.total_amount_in_cents)
    end

    consolidated_invoice.period_start_date = dividend_round.issued_at.to_date
    consolidated_invoice.period_end_date = dividend_round.issued_at.to_date
    consolidated_invoice.invoice_amount_cents = dividend_round.total_amount_in_cents
    consolidated_invoice.flexile_fee_cents = flexile_fee_cents
    consolidated_invoice.transfer_fee_cents = 0
    consolidated_invoice.total_cents = consolidated_invoice.invoice_amount_cents +
                                       consolidated_invoice.transfer_fee_cents +
                                       consolidated_invoice.flexile_fee_cents

    consolidated_invoice.save!
    dividend_round.update!(consolidated_invoice:)
    consolidated_invoice
  end

  private
    def company
      @_company ||= dividend_round.company
    end
end

# frozen_string_literal: true

class FinalizeAndChargeForDividendRound
  def initialize(dividend_computation:)
    @dividend_computation = dividend_computation
  end

  def perform
    ApplicationRecord.transaction do
      dividend_round = dividend_computation.generate_dividends
      consolidated_invoice = DividendRoundConsolidatedInvoiceCreation.new(dividend_round).process
      ChargeConsolidatedInvoice.new(consolidated_invoice.id).process
      dividend_computation.mark_as_finalized!(dividend_round)
      dividend_round
    end
  end

  private
    attr_reader :dividend_computation
end

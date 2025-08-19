# frozen_string_literal: true

class DividendRoundConsolidatedInvoiceCreation
  attr_reader :dividend_round

  def initialize(dividend_round)
    @dividend_round = dividend_round
  end

  def process
    Rails.logger.info("Starting dividend consolidated invoice creation for dividend round #{dividend_round.id}")

    raise "Company must be active" unless company.active?
    raise "Company must have bank account ready" unless company.bank_account_ready?
    raise "Dividend round must be in #{DividendRound::ISSUED} status" unless dividend_round.status == DividendRound::ISSUED
    raise "Dividend round already has consolidated invoice" if dividend_round.consolidated_invoice.present?

    Rails.logger.info("Creating consolidated invoice for dividend round #{dividend_round.id}, amount: #{dividend_round.total_amount_in_cents} cents")

    consolidated_invoice = company.consolidated_invoices.build(
      invoice_date: Date.current,
      invoice_number: "FX-DIV-#{company.consolidated_invoices.count + 1}",
      status: ConsolidatedInvoice::SENT,
      period_start_date: dividend_round.issued_at.to_date,
      period_end_date: dividend_round.issued_at.to_date,
      invoice_amount_cents: dividend_round.total_amount_in_cents,

      # This should be a sum of Flexile fees for each dividend round investor (or dividend of that investor)
      flexile_fee_cents: 0,

      # Unclear what should be set here
      # Either calculate fee of transfer to Flexile's Wise account
      # Or sum of fees of transfers to investors
      transfer_fee_cents: 0,

      # Sum of invoice_amount_cents, flexile_fee_cents, transfer_fee_cents
      total_cents: dividend_round.total_amount_in_cents
    )

    consolidated_invoice.consolidated_invoices_dividend_rounds.build(
      dividend_round: dividend_round
    )
    consolidated_invoice.save!

    Rails.logger.info("Successfully created consolidated invoice #{consolidated_invoice.id} for dividend round #{dividend_round.id}")

    consolidated_invoice
  end

  private
    def company
      @_company ||= dividend_round.company
    end

  # calculate_wise_fee_for_dividend_round

  # def calculate_wise_fee_cents
  #   # You'll need to implement this method
  #   # It should call Wise API to get a quote
  #   wise_fee = get_wise_quote_fee
  #   (wise_fee * 100).round
  # end

  # def get_wise_quote_fee
  #   # This would need to be implemented
  #   # Similar to equity buybacks but for dividend payouts
  #   payout_service = Wise::PayoutApi.new

  #   # Create a quote for the dividend amount
  #   quote = payout_service.create_quote(
  #     target_currency: "USD",  # or whatever currency you're using
  #     amount: dividend_round.total_amount_in_usd,
  #     recipient_id: some_recipient_id  # You'd need to determine this
  #   )

  #   # Extract the fee
  #   payment_option = quote["paymentOptions"].find { _1["payIn"] == "BALANCE" }
  #   payment_option.dig("fee", "total")
  # end
end

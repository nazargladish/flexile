# frozen_string_literal: true

class MarkDividendRoundsReadyForPaymentJob
  include Sidekiq::Job
  sidekiq_options retry: 0

  def perform
    Rails.logger.info("Starting MarkDividendRoundsReadyForPaymentJob")

    # Find dividend rounds that:
    # 1. Have a consolidated invoice
    # 2. Have a successful consolidated payment (funds pulled from company)
    # 3. Have a successful payout to Wise (money moved from Stripe to Wise)
    # 4. Are not already marked as ready for payment
    # 5. Are in the past (issued_at is in the past)

    eligible_count = eligible_dividend_rounds.count
    Rails.logger.info("Found #{eligible_count} eligible dividend rounds for marking as ready for payment")

    if eligible_count == 0
      Rails.logger.info("No eligible dividend rounds found, job completed")
      return
    end

    eligible_dividend_rounds.find_each do |dividend_round|
      Rails.logger.info("Processing dividend round #{dividend_round.id} (company: #{dividend_round.company_id}, amount: #{dividend_round.total_amount_in_cents} cents)")

      # Mark as ready for payment
      dividend_round.update!(ready_for_payment: true)
      Rails.logger.info("Marked dividend round #{dividend_round.id} as ready_for_payment: true")

      # Send dividend issuance emails
      Rails.logger.info("Sending dividend issuance emails for dividend round #{dividend_round.id}")

      # TODO(naz): Should it be called here or earlier?
      dividend_round.send_dividend_emails

      Rails.logger.info("Successfully processed dividend round #{dividend_round.id}")
    end

    Rails.logger.info("Completed MarkDividendRoundsReadyForPaymentJob, processed #{eligible_count} dividend rounds")
  end

  private
    def eligible_dividend_rounds
      Rails.logger.debug("Building query for eligible dividend rounds")

      query = DividendRound.joins(:consolidated_invoices)
                           .joins(consolidated_invoices: :consolidated_payments)
                           .where(ready_for_payment: false)
                           .where(consolidated_invoices: { status: ConsolidatedInvoice::PAID })
                           .where("dividend_rounds.issued_at <= ?", Time.current)
                           .distinct

      Rails.logger.debug("Query built: #{query.to_sql}")
      query
    end
end

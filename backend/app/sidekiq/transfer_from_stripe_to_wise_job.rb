# frozen_string_literal: true

class TransferFromStripeToWiseJob
  include Sidekiq::Job
  sidekiq_options retry: 5

  def perform
    Rails.logger.info("Starting TransferFromStripeToWiseJob")

    eligible_count = eligible_records.count
    Rails.logger.info("Found #{eligible_count} eligible consolidated payments for transfer to Wise")

    if eligible_count == 0
      Rails.logger.info("No eligible consolidated payments found, job completed")
      return
    end

    eligible_records.find_each do |consolidated_payment|
      Rails.logger.info("Processing consolidated payment #{consolidated_payment.id} (dividend_related: #{consolidated_payment.consolidated_invoice.is_dividend_related?})")

      create_payout_for_consolidated_payment_if_possible(consolidated_payment)
    end

    Rails.logger.info("Completed TransferFromStripeToWiseJob, processed #{eligible_count} consolidated payments")
  end

  private
    def create_payout_for_consolidated_payment_if_possible(consolidated_payment)
      Rails.logger.info("Attempting to create payout for consolidated payment #{consolidated_payment.id}")

      CreatePayoutForConsolidatedPayment.new(consolidated_payment).perform!

      Rails.logger.info("Successfully created payout for consolidated payment #{consolidated_payment.id}")
    rescue CreatePayoutForConsolidatedPayment::Error => e
      Rails.logger.debug("Skipping consolidated payment #{consolidated_payment.id}: #{e.message}")
      # do nothing
    end

    def eligible_records
      Rails.logger.debug("Building query for eligible consolidated payments")

      query = ConsolidatedPayment.where(stripe_payout_id: nil).where("trigger_payout_after < ?", Time.current)

      Rails.logger.debug("Query built: #{query.to_sql}")
      query
    end
end

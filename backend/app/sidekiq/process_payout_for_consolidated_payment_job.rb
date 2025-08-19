# frozen_string_literal: true

class ProcessPayoutForConsolidatedPaymentJob
  include Sidekiq::Job
  sidekiq_options retry: 5

  def perform(consolidated_payment_id)
    self.consolidated_payment = ConsolidatedPayment.find(consolidated_payment_id)
    Rails.logger.info("Processing payout for consolidated payment #{consolidated_payment.id} (dividend_related: #{consolidated_payment.consolidated_invoice.is_dividend_related?})")

    return if processed?

    payout = Stripe::Payout.retrieve(consolidated_payment.stripe_payout_id)
    Rails.logger.info("Retrieved Stripe payout #{payout.id} with status: #{payout.status}")

    consolidated_payment.with_lock do
      return if processed?

      # https://docs.stripe.com/api/payouts/object#payout_object-status
      case payout.status
      when "paid"
        Rails.logger.info("Payout paid for consolidated payment #{consolidated_payment.id}")
        process_as_paid!
      else
        Rails.logger.error("Unsupported payout status: #{payout.status} for consolidated payment #{consolidated_payment.id}")
        raise "Unsupported payout status: #{payout.status}"
      end
    end
  end

  private
    attr_accessor :consolidated_payment

    def process_as_paid!
      Rails.logger.info("Processing paid payout for consolidated payment #{consolidated_payment.id}")

      consolidated_payment.update!(succeeded_at: Time.current)
      consolidated_invoice = consolidated_payment.consolidated_invoice

      # Only trigger payments for non-dividend consolidated invoices
      unless consolidated_invoice.is_dividend_related?
        Rails.logger.info("Non-dividend consolidated invoice, triggering payments for #{consolidated_invoice.id}")
        consolidated_invoice.trigger_payments
      else
        Rails.logger.info("Dividend-related consolidated invoice #{consolidated_invoice.id}, skipping payment trigger")
      end

      Rails.logger.info("Marking consolidated invoice #{consolidated_invoice.id} as paid")
      consolidated_invoice.mark_as_paid!(timestamp: Time.current)

      Rails.logger.info("Successfully processed payout for consolidated payment #{consolidated_payment.id}")
    end

    def processed?
      # This only handles the case where the record was updated when a payout was paid, which indicates that
      # the record was "processed" by this job
      consolidated_payment.succeeded_at.present?
    end
end

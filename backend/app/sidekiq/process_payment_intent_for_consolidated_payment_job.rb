# frozen_string_literal: true

class ProcessPaymentIntentForConsolidatedPaymentJob
  include Sidekiq::Job
  sidekiq_options retry: 5

  def perform(consolidated_payment_id)
    consolidated_payment = ConsolidatedPayment.find(consolidated_payment_id)
    Rails.logger.info("Processing payment intent for consolidated payment #{consolidated_payment.id} (dividend_related: #{consolidated_payment.consolidated_invoice.is_dividend_related?})")

    return if consolidated_payment.processed?

    payment_intent = Stripe::PaymentIntent.retrieve(consolidated_payment.stripe_payment_intent_id)
    Rails.logger.info("Retrieved Stripe payment intent #{payment_intent.id} with status: #{payment_intent.status}")

    consolidated_payment.with_lock do
      return if consolidated_payment.processed?

      # https://docs.stripe.com/payments/paymentintents/lifecycle
      case payment_intent.status
      when "succeeded"
        Rails.logger.info("Payment intent succeeded for consolidated payment #{consolidated_payment.id}")
        process_as_succeeded!(consolidated_payment, payment_intent)
      when "requires_payment_method"
        Rails.logger.warn("Payment intent requires payment method for consolidated payment #{consolidated_payment.id}")
        process_as_failed!(consolidated_payment, payment_intent)
      when "canceled"
        Rails.logger.warn("Payment intent canceled for consolidated payment #{consolidated_payment.id}")
        process_as_canceled!(consolidated_payment, payment_intent)
      else
        Rails.logger.error("Unsupported payment intent status: #{payment_intent.status} for consolidated payment #{consolidated_payment.id}")
        raise "Unsupported payment intent status: #{payment_intent.status}"
      end
    end
  end

  private
    # Stripe ACH Debits from a Business account can be disputed within 2 days
    DISPUTE_WINDOW = 2.days

    def process_as_succeeded!(consolidated_payment, payment_intent)
      company = consolidated_payment.company
      charge = Stripe::Charge.retrieve(id: payment_intent.latest_charge, expand: ["balance_transaction"])
      trigger_payout_after = Time.zone.at(charge.balance_transaction.available_on)
      trigger_payout_after += DISPUTE_WINDOW unless company.is_trusted?
      bank_account_last_four = charge["payment_method_details"]["us_bank_account"]["last4"]

      Rails.logger.info("Updating consolidated payment #{consolidated_payment.id} as succeeded, trigger_payout_after: #{trigger_payout_after}")

      consolidated_payment.update!(
        status: ConsolidatedPayment::SUCCEEDED,
        stripe_fee_cents: charge.balance_transaction.fee,
        trigger_payout_after:,
        bank_account_last_four:
      )

      CreateConsolidatedInvoiceReceiptJob.perform_async(
        consolidated_payment.id,
        Time.at(charge["created"]).utc.to_fs(:long_date),
      )

      Rails.logger.info("Successfully processed payment intent for consolidated payment #{consolidated_payment.id}")
    end

    def process_as_failed!(consolidated_payment, payment_intent)
      Rails.logger.error("Processing failed payment intent for consolidated payment #{consolidated_payment.id}")

      consolidated_payment.update!(status: ConsolidatedPayment::FAILED)
      consolidated_payment.balance_transactions.create!(
        company: consolidated_payment.company,
        amount_cents: -payment_intent.amount,
        transaction_type: BalanceTransaction::PAYMENT_FAILED
      )
      consolidated_payment.consolidated_invoice.update!(status: ConsolidatedInvoice::FAILED)

      Rails.logger.error("Payment failed for consolidated payment #{consolidated_payment.id}, amount: #{payment_intent.amount}")
      Bugsnag.notify("Stripe payment failed: #{consolidated_payment.id} - stripe object: #{payment_intent}")
    end

    def process_as_canceled!(consolidated_payment, payment_intent)
      Rails.logger.warn("Processing canceled payment intent for consolidated payment #{consolidated_payment.id}")

      consolidated_payment.update!(status: ConsolidatedPayment::CANCELLED)
      consolidated_payment.balance_transactions.create!(
        company: consolidated_payment.company,
        amount_cents: -payment_intent.amount,
        transaction_type: BalanceTransaction::PAYMENT_CANCELLED
      )

      Rails.logger.warn("Payment canceled for consolidated payment #{consolidated_payment.id}, amount: #{payment_intent.amount}")
      Bugsnag.notify("Stripe payment cancelled: #{consolidated_payment.id} - stripe object: #{payment_intent}")
    end
end

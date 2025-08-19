# frozen_string_literal: true

class CreatePayoutForConsolidatedPayment
  class Error < StandardError; end

  def initialize(consolidated_payment)
    @consolidated_payment = consolidated_payment
  end

  def perform!
    Rails.logger.info("Starting payout creation for consolidated payment #{consolidated_payment.id} (dividend_related: #{consolidated_payment.consolidated_invoice.is_dividend_related?})")

    raise Error, "Not ready for payout yet" if consolidated_payment.trigger_payout_after > Time.current

    Rails.logger.info("Consolidated payment is ready for payout, proceeding...")

    stripe_charge = consolidated_payment.stripe_payment_intent.latest_charge
    Rails.logger.info("Retrieved Stripe charge #{stripe_charge.id} for consolidated payment #{consolidated_payment.id}")

    raise Error, "Stripe charge has been refunded" if stripe_charge.refunded
    raise Error, "Stripe charge has been disputed" if stripe_charge.disputed

    Rails.logger.info("Stripe charge validation passed - not refunded or disputed")

    consolidated_invoice = consolidated_payment.consolidated_invoice
    cents_to_wise = consolidated_invoice.transfer_fee_cents +
      consolidated_invoice.invoice_amount_cents

    Rails.logger.info("Calculated payout amount: #{cents_to_wise} cents (transfer_fee: #{consolidated_invoice.transfer_fee_cents}, invoice_amount: #{consolidated_invoice.invoice_amount_cents})")

    Rails.logger.info("Creating Stripe payout for consolidated payment #{consolidated_payment.id}, amount: #{cents_to_wise} cents")

    begin
      payout = Stripe::Payout.create({
        amount: cents_to_wise,
        currency: "usd",
        description: "Flexile Consolidated Invoice #{consolidated_invoice.id}",
        statement_descriptor: "Flexile",
        metadata: {
          consolidated_invoice: consolidated_invoice.id,
          consolidated_payment: consolidated_payment.id,
        },
      })

      Rails.logger.info("Successfully created Stripe payout #{payout.id} for consolidated payment #{consolidated_payment.id}")

      Rails.logger.info("Updating consolidated payment with payout ID #{payout.id}")
      consolidated_payment.update!(stripe_payout_id: payout.id)
      Rails.logger.info("Updated consolidated payment #{consolidated_payment.id} with payout ID #{payout.id}")

    rescue Stripe::StripeError => e
      Rails.logger.error("Stripe error during payout creation: #{e.message}")
      Rails.logger.error("Stripe error class: #{e.class}")
      if e.respond_to?(:json_body)
        Rails.logger.error("Stripe error details: #{e.json_body}")
      end
      raise Error, "Stripe payout creation failed: #{e.message}"
    rescue StandardError => e
      Rails.logger.error("Unexpected error during payout creation: #{e.message}")
      Rails.logger.error("Error class: #{e.class}")
      Rails.logger.error("Backtrace: #{e.backtrace.first(5).join("\n")}")
      raise Error, "Unexpected error during payout creation: #{e.message}"
    end
  end

  private
    attr_reader :consolidated_payment
end

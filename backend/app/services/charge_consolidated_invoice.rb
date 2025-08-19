# frozen_string_literal: true

class ChargeConsolidatedInvoice
  def initialize(id)
    @consolidated_invoice_id = id
  end

  def process
    consolidated_invoice = ConsolidatedInvoice.find(@consolidated_invoice_id)
    company = consolidated_invoice.company

    Rails.logger.info("Starting fund pull for consolidated invoice #{consolidated_invoice.id} (dividend_related: #{consolidated_invoice.is_dividend_related?})")

    raise "Company does not have a bank account set up" unless company.bank_account_ready?

    begin
      stripe_setup_intent = company.bank_account.stripe_setup_intent
      Rails.logger.info("Creating Stripe payment intent for consolidated invoice #{consolidated_invoice.id}, amount: #{consolidated_invoice.total_cents} cents")

      intent = Stripe::PaymentIntent.create({
        payment_method_types: ["us_bank_account"],
        payment_method: stripe_setup_intent.payment_method,
        customer: stripe_setup_intent.customer,
        confirm: true,
        amount: consolidated_invoice.total_cents,
        currency: "USD",
        expand: ["latest_charge"],
        capture_method: "automatic",
      })

      Rails.logger.info("Successfully created Stripe payment intent #{intent.id} for consolidated invoice #{consolidated_invoice.id}")

    rescue Stripe::StripeError => e
      Rails.logger.error("Stripe error during fund pull for consolidated invoice #{consolidated_invoice.id}: #{e.message}")
      consolidated_invoice.update!(status: Invoice::FAILED)
      raise e
    end

    consolidated_payment = consolidated_invoice.consolidated_payments.create!(
      stripe_payment_intent_id: intent.id,
      stripe_transaction_id: intent.latest_charge.id,
    )

    Rails.logger.info("Created consolidated payment #{consolidated_payment.id} for consolidated invoice #{consolidated_invoice.id}")

    company.consolidated_payment_balance_transactions.create!(
      consolidated_payment:,
      transaction_type: BalanceTransaction::PAYMENT_INITIATED,
      amount_cents: intent.latest_charge.amount,
    )

    Rails.logger.info("Created balance transaction for consolidated payment #{consolidated_payment.id}")

    # Only trigger payments for non-dividend consolidated invoices
    # TODO(naz): should we send dividend payments for trusted companies immediately too?
    if company.is_trusted? && !consolidated_invoice.is_dividend_related?
      Rails.logger.info("Company is trusted and not dividend-related, triggering payments for consolidated invoice #{consolidated_invoice.id}")
      consolidated_invoice.trigger_payments
    elsif consolidated_invoice.is_dividend_related?
      Rails.logger.info("Dividend-related consolidated invoice #{consolidated_invoice.id}, skipping payment trigger")
    else
      Rails.logger.info("Company not trusted, skipping payment trigger for consolidated invoice #{consolidated_invoice.id}")
    end

    Rails.logger.info("Completed fund pull process for consolidated invoice #{consolidated_invoice.id}")
  end
end

# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "VCR Stripe Setup", :vcr_stripe do
  describe "basic Stripe API interaction" do
    it "can create a Stripe customer with VCR recording" do
      # This test verifies that VCR correctly intercepts Stripe API calls
      customer = Stripe::Customer.create({
        name: "Test Customer",
        email: "test@example.com",
      })

      expect(customer.id).to start_with("cus_")
      expect(customer.email).to eq("test@example.com")
      expect(customer.name).to eq("Test Customer")
    end

    it "can create a setup intent with VCR recording" do
      # First create a customer
      customer = Stripe::Customer.create({
        name: "Test Company",
        email: "company@example.com",
      })

      # Then create a setup intent
      setup_intent = Stripe::SetupIntent.create({
        customer: customer.id,
        payment_method_types: ["us_bank_account"],
        usage: "off_session",
      })

      expect(setup_intent.id).to start_with("seti_")
      expect(setup_intent.customer).to eq(customer.id)
      expect(setup_intent.payment_method_types).to include("us_bank_account")
    end
  end
end

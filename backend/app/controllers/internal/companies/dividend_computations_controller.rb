# frozen_string_literal: true

class Internal::Companies::DividendComputationsController < Internal::Companies::BaseController
  before_action :set_dividend_computation, only: [:show, :approve]

  def index
    authorize DividendComputation

    dividend_computations = Current.company.dividend_computations
      .pending_approval
      .with_shareholder_count
      .order(id: :desc)
      .map do |computation|
        DividendComputationPresenter.new(computation).props
      end

    render json: dividend_computations
  end

  def show
    authorize @dividend_computation

    computation_data = DividendComputationPresenter.new(@dividend_computation).props
    investor_breakdown = @dividend_computation.broken_down_by_investor

    render json: computation_data.merge(investor_breakdown:)
  end

  def create
    authorize DividendComputation

    dividend_computation = DividendComputationGeneration.new(
      Current.company,
      dividends_issuance_date: dividend_computation_params[:dividends_issuance_date]&.to_date || Date.current,
      amount_in_usd: dividend_computation_params[:amount_in_usd],
      return_of_capital: dividend_computation_params[:return_of_capital]
    ).process

    render json: { id: dividend_computation.id }, status: :created
  rescue StandardError => e
    render json: { error_message: e.message }, status: :unprocessable_entity
  end

  def approve
    authorize @dividend_computation

    Rails.logger.info("Starting approval process for dividend computation #{@dividend_computation.id}")

    if @dividend_computation.approved?
      Rails.logger.warn("Dividend computation #{@dividend_computation.id} already approved, skipping")
      render json: { error_message: "This dividend computation has already been approved" }, status: :unprocessable_entity
      return
    end

    dividend_round = nil

    ActiveRecord::Base.transaction do
      Rails.logger.info("Creating dividend round for computation #{@dividend_computation.id}")

      # Create dividend round
      dividend_round = @dividend_computation.generate_dividends

      Rails.logger.info("Created dividend round #{dividend_round.id} with #{dividend_round.dividends.count} dividends")

      # Create consolidated invoice
      # TODO(naz): There should be some wrapper service that both invoices and charges, so that it can be called from Rails console nicely
      consolidated_invoice = DividendRoundConsolidatedInvoiceCreation.new(dividend_round).process

      Rails.logger.info("Created consolidated invoice #{consolidated_invoice.id} for dividend round #{dividend_round.id}")

      # Mark computation as approved
      @dividend_computation.mark_as_approved!(dividend_round)

      Rails.logger.info("Marked dividend computation #{@dividend_computation.id} as approved")

      # Trigger fund pull separately
      Rails.logger.info("Initiating fund pull for consolidated invoice #{consolidated_invoice.id}")
      ChargeConsolidatedInvoice.new(consolidated_invoice.id).process

      Rails.logger.info("Fund pull initiated for consolidated invoice #{consolidated_invoice.id}")
    end

    Rails.logger.info("Successfully completed approval process for dividend computation #{@dividend_computation.id}")

    render json: { id: dividend_round.id }, status: :created
  rescue StandardError => e
    Rails.logger.error("Error during dividend computation approval: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render json: { error_message: e.message }, status: :unprocessable_entity
  end

  private
    def set_dividend_computation
      @dividend_computation = Current.company.dividend_computations.find(params[:id])
    end

    def dividend_computation_params
      params.require(:dividend_computation).permit(:amount_in_usd, :dividends_issuance_date, :return_of_capital)
    end
end

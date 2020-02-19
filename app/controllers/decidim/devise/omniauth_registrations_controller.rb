# frozen_string_literal: true

module Decidim
  module Devise
    # This controller customizes the behaviour of Devise::Omniauthable.
    class OmniauthRegistrationsController < ::Devise::OmniauthCallbacksController
      include FormFactory
      include Decidim::DeviseControllers

      prepend_before_action :manage_omniauth_authorization, except: [:logout]

      after_action :grant_omniauth_authorization, except: [:logout]

      # skip_before_action :verify_authenticity_token, if: :is_saml_callback?

      def new
        @form = form(OmniauthRegistrationForm).from_params(params[:user])
      end

      def create
        form_params = user_params_from_oauth_hash || params[:user]

        @form = form(OmniauthRegistrationForm).from_params(form_params)
        @form.email ||= verified_email

        CreateOmniauthRegistration.call(@form, verified_email) do
          on(:ok) do |user|
            if user.active_for_authentication?
              sign_in_and_redirect user, event: :authentication
              set_flash_message :notice, :success, kind: provider_name(@form.provider)
            else
              expire_data_after_sign_in!
              user.resend_confirmation_instructions unless user.confirmed?
              redirect_to decidim.root_path
              flash[:notice] = t("devise.registrations.signed_up_but_unconfirmed")
            end
          end

          on(:invalid) do
            set_flash_message :notice, :success, kind: provider_name(@form.provider)
            render :new
          end

          on(:error) do |user|
            if user.errors[:email]
              set_flash_message :alert, :failure, kind: provider_name(@form.provider), reason: t("decidim.devise.omniauth_registrations.create.email_already_exists")
            end

            render :new
          end
        end
      end

      def logout

        %w(notice success alert error warning info primary secondary omniauth logout).each do |type|
          flash.keep(type.to_sym)
        end

        # if params["state"].present? && params["state"] != stored_state
        #     # flash[:logout] = t("devise.registrations.logout.success", kind: provider_name(params[:provider]))
        #     flash[:alert] = t("devise.registrations.logout.error", kind: provider_name(params[:provider]))
        # end

        redirect_to after_sign_in_path_for(current_user)
      end

      def after_sign_in_path_for(user)
        if logout_uri_is_valid?
          oauth_data[:logout]
        elsif !pending_redirect?(user) && first_login_and_not_authorized?(user)
          decidim_verifications.authorizations_path
        else
          super
        end
      end

      # Calling the `stored_location_for` method removes the key, so in order
      # to check if there's any pending redirect after login I need to call
      # this method and use the value to set a pending redirect. This is the
      # only way to do this without checking the session directly.
      def pending_redirect?(user)
        store_location_for(user, stored_location_for(user))
      end

      def first_login_and_not_authorized?(user)
        user.is_a?(User) && user.sign_in_count == 1 && Decidim::Verifications.workflows.any? && user.verifiable?
      end

      def action_missing(action_name)
        return send(:create) if devise_mapping.omniauthable? && current_organization.enabled_omniauth_providers.keys.include?(action_name.to_sym)

        raise AbstractController::ActionNotFound, "The action '#{action_name}' could not be found for Decidim::Devise::OmniauthCallbacksController"
      end

      def manage_omniauth_authorization

        # Rails.logger.debug "+++++++++++++++++++++++++"
        # Rails.logger.debug "OmniauthRegistrationsController.manage_omniauth_authorization"
        # Rails.logger.debug params
        # Rails.logger.debug "with current_user" if current_user
        # Rails.logger.debug "location_for :user --> " + store_location_for(:user, stored_location_for(:user)).to_s
        # Rails.logger.debug "location_for :redirect --> " + store_location_for(:redirect, stored_location_for(:redirect)).to_s
        # Rails.logger.debug "match : " + ( store_location_for(:user, stored_location_for(:user)) =~ /^\/#{params[:action]}\/$/ ).inspect
        # Rails.logger.debug "omniauth_origin --> " + request.env["omniauth.origin"].split("?").first.to_s if request.env["omniauth.origin"].present?
        # Rails.logger.debug "new_user_session_url --> " + decidim.new_user_session_path.split("?").first.to_s
        # Rails.logger.debug "+++++++++++++++++++++++++"

        location = store_location_for(:user, stored_location_for(:user))
        return unless location.present? && !!location.match(/^\/#{params[:action]}\/$/)

        if current_user
          @verified_email = current_user.email
        end

        if request.env["omniauth.origin"].present? && (request.env["omniauth.origin"].split("?").first != decidim.new_user_session_url.split("?").first)
          store_location_for(:user, request.env["omniauth.origin"])
        else
          store_location_for(:user, stored_location_for(:redirect))
        end
      end

      def grant_omniauth_authorization

        # Rails.logger.debug "+++++++++++++++++++++++++"
        # Rails.logger.debug "OmniauthRegistrationsController.grant_omniauth_authorization"
        # Rails.logger.debug oauth_data.to_json if oauth_data
        # Rails.logger.debug "+++++++++++++++++++++++++"

        return unless Decidim.authorization_workflows.one?{ |a| a.try(:omniauth_provider) == params[:action] }

        # just to be safe
        return unless current_user

        # current_user.update_column(:managed, true) if current_user.email.blank?

        @workflow = Decidim.authorization_workflows.find{ |a| a.try(:omniauth_provider) == params[:action] }

        @form = Decidim::Verifications::Omniauth::OmniauthAuthorizationForm.from_params(user: current_user, provider: @workflow.omniauth_provider, oauth_data: oauth_data[:info])

        @authorization = Decidim::Authorization.find_or_initialize_by(
          user: current_user,
          name: @workflow.name
        )

        Decidim::Verifications::Omniauth::ConfirmOmniauthAuthorization.call(@authorization, @form) do
          on(:ok) do
            flash[:omniauth] = t("authorizations.new.success", scope: "decidim.verifications.omniauth", locale: current_user.locale)
          end
          on(:invalid) do
            flash[:alert] = @form.errors.to_h.values.join(' ')
            store_location_for(:user, decidim.root_path)
          end
        end
      end

      private

      def oauth_data
        @oauth_data ||= oauth_hash.slice(:provider, :uid, :info, :logout)
      end

      # Private: Create form params from omniauth hash
      # Since we are using trusted omniauth data we are generating a valid signature.
      def user_params_from_oauth_hash
        return nil if oauth_data.empty?

        {
          provider: oauth_data[:provider],
          uid: oauth_data[:uid],
          name: oauth_data[:info][:name],
          nickname: oauth_data[:info][:nickname],
          oauth_signature: OmniauthRegistrationForm.create_signature(oauth_data[:provider], oauth_data[:uid]),
          avatar_url: oauth_data[:info][:image],
          raw_data: oauth_hash
        }
      end

      def verified_email
        @verified_email ||= oauth_data.dig(:info, :email)
      end

      def oauth_hash
        raw_hash = request.env["omniauth.auth"]
        return {} unless raw_hash

        raw_hash.deep_symbolize_keys
      end

      def logout_uri_is_valid?
        oauth_data[:logout] &&
          oauth_data[:logout] =~ URI::DEFAULT_PARSER.make_regexp
      end

      def stored_state
        session.delete('omniauth.state')
      end

      def provider_name(provider)
        if Rails.application.secrets.dig(:omniauth, provider.to_sym, :provider_name).present?
          Rails.application.secrets.dig(:omniauth, provider.to_sym, :provider_name)
        else
          provider.capitalize
        end
      end

      def is_saml_callback?
        request.path.end_with?("/callback") &&
          request.env["omniauth.strategy"].options[:idp_sso_target_url].present? &&
          URI.parse(request.origin).host == URI.parse(request.env["omniauth.strategy"].options[:idp_sso_target_url]).host
      end
    end
  end
end
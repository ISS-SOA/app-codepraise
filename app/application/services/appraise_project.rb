# frozen_string_literal: true

require 'dry/transaction'

module CodePraise
  module Service
    # Analyzes contributions to a project
    class AppraiseProject
      include Dry::Transaction

      step :ensure_project
      step :retrieve_folder_appraisal
      step :reify_appraisal

      private

      def ensure_project(input)
        project_fullname = input[:requested].project_fullname

        # If already in watched list, skip API call
        if input[:watched_list].include?(project_fullname)
          Success(input.merge(project_added: false))
        else
          # Auto-add project via API
          add_project_to_api(input)
        end
      end

      def add_project_to_api(input)
        result = Gateway::Api.new(CodePraise::App.config)
          .add_project(input[:requested].owner_name, input[:requested].project_name)

        if result.success?
          Success(input.merge(project_added: true))
        else
          Representer::HttpResponse
            .new(OpenStruct.new)
            .from_json(result.payload)
            .then { |error| Failure(error.message) }
        end
      rescue StandardError
        Failure('Cannot access this project — please check the URL or try again later')
      end

      def retrieve_folder_appraisal(input)
        input[:response] = Gateway::Api.new(CodePraise::App.config)
          .appraise(input[:requested])

        if input[:response].success?
          Success(input)
        else
          Representer::HttpResponse
            .new(OpenStruct.new)
            .from_json(input[:response].payload)
            .then { |error| Failure(error.message) }
        end
      rescue StandardError
        Failure('Cannot appraise projects right now; please try again later')
      end

      def reify_appraisal(input)
        unless input[:response].processing?
          Representer::ProjectFolderContributions.new(OpenStruct.new)
            .from_json(input[:response].payload)
            .then { input[:appraised] = _1 }
        end

        Success(input)
      rescue StandardError
        Failure('Error in our appraisal report -- please try again')
      end

      # Helper methods

      def full_request_path(input)
        [input[:requested].owner_name,
         input[:requested].project_name,
         input[:requested].folder_name].join('/')
      end
    end
  end
end

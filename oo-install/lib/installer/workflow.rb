require 'installer/exceptions'
require 'installer/helpers'
require 'installer/executable'
require 'installer/question'

module Installer
  class Workflow
    include Installer::Helpers

    class << self
      def ids
        @ids ||= workflows_cache.map{ |workflow| workflow.id }
      end

      def list(context)
        workflows_cache.select{ |workflow| workflow.contexts[context] }
      end

      def find id
        unless ids.include?(id)
          raise Installer::WorkflowNotFoundException.new "Could not find a workflow with id #{id}."
        end
        workflows_cache.select{ |workflow| workflow.id == id }[0]
      end

      def supported_versions_for_id id
        workflows_cache.select{ |workflow| workflow.id == id }[0].versions
      end

      private
      def file_path
        @file_path ||= gem_root_dir + '/conf/workflows.yml'
      end

      def workflows_cache
        @workflows_cache ||= validate_and_return_config
      end

      def required_fields
        %w{ID Name Summary Executable}
      end

      def parse_config_file
        unless File.exists?(file_path)
          raise Installer::WorkflowFileNotFoundException.new
        end
        yaml = YAML.load_stream(open(file_path))
        if yaml.is_a?(Array)
          # Ruby 1.9.3+
          return yaml
        else
          # Ruby 1.8.7
          return yaml.documents
        end
      end

      def validate_and_return_config
        parse_config_file.each do |workflow|
          required_fields.each do |field|
            if not workflow.has_key?(field)
              raise Installer::WorkflowMissingRequiredSettingException.new "Required field #{field} missing from workflow entry:\n#{workflow.inspect}\n\n"
            end
          end
          # Check for the reserved variable 'version' in Questions
          if workflow.has_key?('Questions') and workflow['Questions'].select{ |q| q['Variable'] == 'version' }.length > 0
            raise Installer::WorkflowQuestionReservedVariableException.new "Workflow question variable 'version' is reserved for use by oo-install"
          end
        end
        parse_config_file.map{ |record| new(record) }
      end
    end

    attr_reader :name, :contexts, :summary, :description, :id, :questions, :executable, :path, :utilities, :versions, :targets

    def initialize config
      @id = config['ID']
      @name = config['Name']
      if config.has_key?('Contexts')
        @contexts = {}
        config['Contexts'].each do |context|
          if not supported_contexts.include?(context.to_sym)
            raise Installer::WorkflowContextNotRecognizedException.new("Workflow context '#{context}' is not supported. Legal values are #{supported_contexts.map{ |c| c.to_s }.join(', ')}.")
          end
          @contexts[context.to_sym] = true
        end
      else
        @contexts = { :origin => true }
      end
      if config.has_key?('Targets')
        @targets = {}
        config['Targets'].each do |target|
          if not supported_targets.include?(target.to_sym)
            raise Installer::WorkflowTargetNotRecognizedException.new("Target '#{target}' is not supported. Legal values are #{supported_targets.map{ |t| t.to_s }.join(', ')}.")
          end
          @targets[target.to_sym] = true
        end
      else
        @targets = { :fedora => true, :rhel => true }
      end
      @summary = config['Summary']
      @description = config['Description']
      @remote_execute = (config.has_key?('RemoteDeployment') and config['RemoteDeployment'].downcase == 'y') ? true : false
      @check_deployment = (config.has_key?('SkipDeploymentCheck') and config['SkipDeploymentCheck'].downcase == 'y') ? false : true
      @check_subscription = (config.has_key?('SubscriptionCheck') and config['SubscriptionCheck'].downcase == 'y') ? true : false
      if config.has_key?('NonDeployment') and config['NonDeployment'].downcase == 'y'
        @non_deployment = true
        @remote_execute = false
        @check_deployment = false
        @check_subscription = false
      else
        @non_deployment = false
      end
      workflow_dir = config.has_key?('WorkflowDir') ? config['WorkflowDir'] : id
      @path = gem_root_dir + "/workflows/" + workflow_dir
      @questions = config.has_key?('Questions') ? config['Questions'].map{ |q| Installer::Question.new(self, q) } : []
      if config.has_key?('Versions')
        @versions = {}
        config['Versions'].each do |version|
          @versions[version.to_s] = true
        end

        # Prepend the version question to the questions list.
        @questions.unshift(
          Installer::Question.new(
            self,
            { 'Text' => "What version do you want to install? (#{versions.keys.sort.join(', ')}) ",
              'Variable' => 'version',
              'AnswerType' => 'version',
            }
          )
        )
      end
      @executable = Installer::Executable.new(self, config['Executable'])
      @utilities = ['yum']
      if config.has_key?('RequiredUtilities')
        @utilities.concat(config['RequiredUtilities'])
      end
    end

    def check_deployment?
      @check_deployment
    end

    def check_subscription?
      @check_subscription
    end

    def remote_execute?
      @remote_execute
    end

    def non_deployment?
      @non_deployment
    end
  end
end

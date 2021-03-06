# encoding: UTF-8
require 'puppet'
require 'kafo_parsers/doc_parser'

module KafoParsers
  # Based on ideas from puppet-parse by Johan van den Dorpe
  # we don't build any tree structure since e.g. params from doc does not
  # have to be defined in puppet DSL and vice versa, we just gather all info
  # we can read from the whole manifest
  class PuppetModuleParser
    @@puppet_initialized = false

    # You can call this method to get all supported information from a given manifest
    #
    # @param [ String ] manifest file path to parse
    # @return [ Hash ] hash containing values, validations, documentation, types, groups and conditions
    def self.parse(file)
      content = new(file)
      docs    = content.docs

      data              = {
          :values      => content.values,
          :validations => content.validations
      }
      data[:parameters] = data[:values].keys
      data.merge!(docs)
      data
    end

    def initialize(file)
      @file = file
      raise ModuleName, "File not found #{file}, check your answer file" unless File.exists?(file)

      unless @@puppet_initialized
        if Puppet::PUPPETVERSION.to_i >= 3
          Puppet.initialize_settings
        else
          Puppet.parse_config
        end
        @@puppet_initialized = true
      end

      env = Puppet::Node::Environment.new
      parser = Puppet::Parser::Parser.new(env)
      parser.import(@file)

      # Find object corresponding to class defined in init.pp in list of hostclasses
      ast_types = parser.environment.known_resource_types.hostclasses.map(&:last)
      @object = ast_types.find { |ast_type| ast_type.file == file }

      # Find object in list of definitions if not found among hostclasses
      if @object.nil?
        ast_types = parser.environment.known_resource_types.definitions.map(&:last)
        @object = ast_types.find { |ast_type| ast_type.file == file }
      end

      parser
    end

    # TODO - store parsed object type (Puppet::Parser::AST::Variable must be dumped later)
    def values
      parameters = {}
      arguments  = @object.respond_to?(:arguments) ? @object.arguments : {}
      arguments.each { |k, v| parameters[k] = v.respond_to?(:value) ? v.value : nil }
      parameters
    end

    def validations(param = nil)
      return [] if @object.code.nil?
      @object.code.select { |stmt| stmt.is_a?(Puppet::Parser::AST::Function) && stmt.name =~ /^validate_/ }
    end

    # returns data in following form
    # {
    #   :docs => { $param1 => 'documentation without types and conditions'}
    #   :types => { $param1 => 'boolean'},
    #   :groups => { $param1 => ['Parameters', 'Advanced']},
    #   :conditions => { $param1 => '$db_type == "mysql"'},
    #   :object_type => 'hostclass' # or definition
    # }
    def docs
      data = { :docs => {}, :types => {}, :groups => {}, :conditions => {}, :object_type => '' }
      if @object.nil?
        raise DocParseError, "no documentation found for manifest #{@file}, parsing error?"
      elsif !@object.doc.nil?
        parser             = DocParser.new(@object.doc).parse
        data[:docs]        = parser.docs
        data[:groups]      = parser.groups
        data[:types]       = parser.types
        data[:conditions]  = parser.conditions
        data[:object_type] = @object.type.to_s
      end
      data
    end
  end
end

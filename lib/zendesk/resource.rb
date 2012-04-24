require 'hashie'
require 'zendesk/actions'
require 'zendesk/association'
require 'zendesk/verbs'

module Zendesk
  class DataResource
    extend Association
    include Zendesk::ParameterWhitelist

    class << self
      def singular_resource_name
        @singular_resource_name ||= to_s.split("::").last.snakecase
      end

      def resource_name
        @resource_name ||= singular_resource_name.plural
      end
    end

    attr_reader :attributes
    def initialize(client, attributes = {}, path = [])
      @client, @attributes, @path = client, Hashie::Mash.new(attributes), path
      @path.push(self.class.resource_name) if @path.empty?
    end

    def method_missing(*args, &blk)
      if @attributes.key?(self.class.singular_resource_name)
        @attributes[self.class.singular_resource_name].send(*args, &blk)
      else
        @attributes.send(*args, &blk)
      end
    end

    def id
      key?(:id) ? method_missing(:id) : nil
    end

    def path
      @path.join("/")
    end

    def to_s
      "#{self.class.singular_resource_name}: #{attributes.inspect}"
    end
    alias :inspect :to_s
  end

  class ReadResource < DataResource
    extend Read
  end

  class CreateResource < DataResource
    extend Create
  end

  class Resource < DataResource 
    extend Read
    extend Create
    extend Destroy
    extend Verbs

    def initialize(*args)
      super
      @destroyed = false
    end

    def destroyed?
      @destroyed
    end

    def new_record?
      id.nil? 
    end

    def save
      return false if destroyed?

      req_path = path
      if new_record?
        method = :post
      else
        method = :put
        req_path += "/#{id}.json"
      end

      response = @client.connection.send(method, req_path) do |req|
        req.body = self.class.whitelist_attributes(attributes, method)
      end

      @attributes.replace(@attributes.deep_merge(response.body))
      true
    rescue Faraday::Error::ClientError => e
      false
    end

    def destroy
      response = @client.connection.delete("#{path}/#{id}.json")
      @destroyed = true
    rescue Faraday::Error::ClientError => e
      false
    end
  end

  private

  # Allows using has and has_many without having class defined yet
  # Guesses at Resource, if it's anything else and the class is later
  # reopened under a different superclass, an error will be thrown
  def self.get_class(resource)
    return false if resource.nil?
    res = resource.to_s.modulize

    begin
      const_get(res)
    rescue NameError
      const_set(res, Class.new(Resource))
    end
  end
end
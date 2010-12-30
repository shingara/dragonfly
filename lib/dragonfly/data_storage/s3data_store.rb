require 'fog'

module Dragonfly
  module DataStorage

    class S3DataStore

      include Configurable
      include Serializer

      # Available options are defined in Fog Storage[http://github.com/geemus/fog/blob/master/lib/fog/aws/storage.rb]
      #
      #     'eu-west-1' => 's3-eu-west-1.amazonaws.com'
      #     'us-east-1' => 's3.amazonaws.com'
      #     'ap-southeast-1' => 's3-ap-southeast-1.amazonaws.com'
      #     'us-west-1' => 's3-us-west-1.amazonaws.com'

      configurable_attr :bucket_name
      configurable_attr :access_key_id
      configurable_attr :secret_access_key
      configurable_attr :region
      configurable_attr :specific_uid
      configurable_attr :use_filesystem, true
      configurable_attr :autocreate_bucket, false

      def initialize(opts={})
        self.bucket_name = opts[:bucket_name]
        self.access_key_id = opts[:access_key_id]
        self.secret_access_key = opts[:secret_access_key]
      end

      def connection
        @connection ||= Fog::AWS::Storage.new(
          :aws_access_key_id => access_key_id,
          :aws_secret_access_key => secret_access_key,
          :region => region
        )
      end

      def create_bucket!
        connection.put_bucket(bucket_name) unless bucket_names.include?(bucket_name)
      end

      def store(temp_object, opts={})
        uid = opts[:path] || generate_uid(temp_object.name || 'file')
        ensure_initialized
        extra_data = temp_object.attributes
        if use_filesystem
          temp_object.file do |f|
            connection.put_object(bucket_name,
                                  uid,
                                  f.read,
                                  s3_metadata_for(extra_data))
          end
        else
          connection.put_object(bucket_name,
                                uid,
                                temp_object.data,
                                s3_metadata_for(extra_data))
        end
        uid
      end

      def retrieve(uid)
        ensure_initialized
        s3_object = connection.get_object(bucket_name, uid)
        [
          s3_object.body,
          parse_s3_metadata(s3_object.headers)
        ]
      rescue Excon::Errors::NotFound => e
        raise DataNotFound, "#{e} - #{uid}"
      end

      def destroy(uid)
        ensure_initialized
        connection.delete_object(bucket_name, uid)
      rescue Excon::Errors::NotFound => e
        raise DataNotFound, "#{e} - #{uid}"
      end

      private

      def bucket_names
        connection.get_service.body['Buckets'].map{|bucket| bucket['Name'] }
      end

      def ensure_initialized
        unless @initialized
          create_bucket! if autocreate_bucket
          @initialized = true
        end
      end

      def generate_uid(name)
        if self.specific_uid.is_a?(Proc)
          self.specific_uid.call(name)
        else
          "#{Time.now.strftime '%Y/%m/%d/%H/%M/%S'}/#{rand(1000)}/#{name.gsub(/[^\w.]+/, '_')}"
        end
      end

      def s3_metadata_for(extra_data)
        {'x-amz-meta-extra' => marshal_encode(extra_data)}
      end

      def parse_s3_metadata(metadata)
        extra_data = metadata['x-amz-meta-extra']
        marshal_decode(extra_data) if extra_data
      end

    end

  end
end

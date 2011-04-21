module Dragonfly
  class Server

    include Loggable
    include Configurable

    configurable_attr :dragonfly_url, '/dragonfly'
    configurable_attr :protect_from_dos_attacks, false
    configurable_attr :url_format, '/:job/:basename.:format'
    configurable_attr :url_host

    extend Forwardable
    def_delegator :url_mapper, :params_in_url

    def initialize(app)
      @app = app
      use_same_log_as(app)
      use_as_fallback_config(app)
    end

    def before_serve(&block)
      self.before_serve_callback = block
    end
    configuration_method :before_serve

    def after_serve(&block)
      self.after_serve_callback = block
    end
    configuration_method :after_serve

    def call(env)
      if dragonfly_url == env["PATH_INFO"]
        dragonfly_response
      elsif (params = url_mapper.params_for(env["PATH_INFO"], env["QUERY_STRING"])) && params['job']
        job = Job.deserialize(params['job'], app)
        job.validate_sha!(params['sha']) if protect_from_dos_attacks
        response = Response.new(job, env)
        catch(:halt) do
          if before_serve_callback && response.served?
            before_serve_callback.call(job, env)
          end
          resp = response.to_response
          if after_serve_callback && resp[0] == 200 && resp[2].is_a?(Dragonfly::TempObject)
            after_serve_callback.call(job, env)
          end
          resp
        end
      else
        [404, {'Content-Type' => 'text/plain', 'X-Cascade' => 'pass'}, ['Not found']]
      end
    rescue Serializer::BadString, Job::InvalidArray => e
      log.warn(e.message)
      [404, {'Content-Type' => 'text/plain'}, ['Not found']]
    rescue Job::NoSHAGiven => e
      [400, {"Content-Type" => 'text/plain'}, ["You need to give a SHA parameter"]]
    rescue Job::IncorrectSHA => e
      [400, {"Content-Type" => 'text/plain'}, ["The SHA parameter you gave (#{e}) is incorrect"]]
    end

    def url_for(job, opts={})
      opts = opts.dup
      host = opts.delete(:host) || url_host
      params = stringify_keys(opts)
      params['job'] = job.serialize
      params['sha'] = job.sha if protect_from_dos_attacks
      url = url_mapper.url_for(params)
      "#{host}#{url}"
    end

    private

    attr_reader :app
    attr_accessor :before_serve_callback
    attr_accessor :after_serve_callback

    def url_mapper
      @url_mapper ||= UrlMapper.new(url_format,
        :job => '\w',
        :basename => '[^\/]',
        :format => '[^\.]'
      )
    end

    def stringify_keys(params)
      params.inject({}) do |hash, (k, v)|
        hash[k.to_s] = v
        hash
      end
    end

    def dragonfly_response
      body = <<-DRAGONFLY
          _o|o_
  _~~---._(   )_.---~~_
 (       . \\ / .       )
  `-.~--'  |=|  '--~.-'
  _~-.~'" /|=|\\ "'~.-~_
 (      ./ |=| \\.      )
  `~~`"`   |=|   `"'ME"
           |-|
           <->
            V
      DRAGONFLY
      [200, {
        'Content-Type' => 'text/plain',
        'Content-Size' => body.bytesize.to_s
        },
        [body]
      ]
    end

  end
end

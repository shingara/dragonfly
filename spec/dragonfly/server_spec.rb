require 'spec_helper'
require 'rack/mock'
require 'rack/cache'

def request(app, path)
  Rack::MockRequest.new(app).get(path)
end

describe Dragonfly::Server do

  describe "responses" do
    
    before(:each) do
      @app = test_app
      @uid = @app.store('HELLO THERE')
      @server = Dragonfly::Server.new(@app)
      @server.url_format = '/media/:job'
      @job = @app.fetch(@uid)
    end
  
    after(:each) do
      @app.destroy(@uid)
    end

    describe "successful urls" do
      before(:each) do
        @server.url_format = '/media/:job/:name.:format'
      end
    
      [
        '',
        '/name',
        '/name.ext'
      ].each do |suffix|
    
        it "should return successfully when given the url with suffix #{suffix.inspect}" do
          url = "/media/#{@job.serialize}#{suffix}"
          response = request(@server, url)
          response.status.should == 200
          response.body.should == 'HELLO THERE'
          response.content_type.should == 'application/octet-stream'
        end
        
      end

      it "should return successfully with the correct sha given and protection on" do
        @server.protect_from_dos_attacks = true
        url = "/media/#{@job.serialize}?sha=#{@job.sha}"
        response = request(@server, url)
        response.status.should == 200
        response.body.should == 'HELLO THERE'
      end

    end

    it "should return successfully even if the job is in the query string" do
      @server.url_format = '/'
      url = "/?job=#{@job.serialize}"
      response = request(@server, url)
      response.status.should == 200
      response.body.should == 'HELLO THERE'
    end

    it "should return a 400 if no sha given but protection on" do
      @server.protect_from_dos_attacks = true
      url = "/media/#{@job.serialize}"
      response = request(@server, url)
      response.status.should == 400
    end
  
    it "should return a 400 if wrong sha given and protection on" do
      @server.protect_from_dos_attacks = true
      url = "/media/#{@job.serialize}?sha=asdfs"
      response = request(@server, url)
      response.status.should == 400
    end

    ['/media', '/media/'].each do |url|
      it "should return a 404 when no job given, e.g. #{url.inspect}" do
        response = request(@server, url)
        response.status.should == 404
        response.body.should == 'Not found'
        response.content_type.should == 'text/plain'
        response.headers['X-Cascade'].should == 'pass'
      end
    end
  
    it "should return a 404 when the url matches but doesn't correspond to a job" do
      response = request(@server, '/media/sadhfasdfdsfsdf')
      response.status.should == 404
      response.body.should == 'Not found'
      response.content_type.should == 'text/plain'
      response.headers['X-Cascade'].should be_nil
    end
  
    it "should return a 404 when the url isn't known at all" do
      response = request(@server, '/jfasd/dsfa')
      response.status.should == 404
      response.body.should == 'Not found'
      response.content_type.should == 'text/plain'
      response.headers['X-Cascade'].should == 'pass'
    end
  
    it "should return a 404 when the url is a well-encoded but bad array" do
      url = "/media/#{Dragonfly::Serializer.marshal_encode([[:egg, {:some => 'args'}]])}"
      response = request(@server, url)
      response.status.should == 404
      response.body.should == 'Not found'
      response.content_type.should == 'text/plain'
      response.headers['X-Cascade'].should be_nil
    end

    it "should return a cacheable response" do
      url = "/media/#{@job.serialize}"
      cache = Rack::Cache.new(@server, :entitystore => 'heap:/')
      response = request(cache, url)
      response.status.should == 200
      response.headers['X-Rack-Cache'].should == "miss, store"
      response = request(cache, url)
      response.status.should == 200
      response.headers['X-Rack-Cache'].should == "fresh"
    end

  end
  
  describe "dragonfly response" do
    before(:each) do
      @app = test_app
      @server = Dragonfly::Server.new(@app)
      @server.url_format = '/media/:job'
    end
    
    it "should return a simple text response" do
      request(@server, '/dragonfly').should be_a_text_response
    end

    it "should be configurable" do
      @server.dragonfly_url = '/hello'
      request(@server, '/hello').should be_a_text_response
      request(@server, '/dragonfly').status.should == 404
    end

    it "should be possible to turn it off" do
      @server.dragonfly_url = nil
      request(@server, '/').status.should == 404
      request(@server, '/dragonfly').status.should == 404
    end
  end

  describe "urls" do
    
    before(:each) do
      @app = test_app
      @server = Dragonfly::Server.new(@app)
      @server.url_format = '/media/:job/:basename.:format'
      @job = @app.fetch('some_uid')
    end
    
    it "should generate the correct url when no basename/format" do
      @server.url_for(@job).should == "/media/#{@job.serialize}"
    end
    
    it "should generate the correct url when there is a basename and no format" do
      @server.url_for(@job, :basename => 'hello').should == "/media/#{@job.serialize}/hello"
    end
    
    it "should generate the correct url when there is a basename and different format" do
      @server.url_for(@job, :basename => 'hello', :format => 'gif').should == "/media/#{@job.serialize}/hello.gif"
    end

    it "should add extra params to the url query string" do
      @server.url_for(@job, :a => 'thing', :b => 'nuther').should == "/media/#{@job.serialize}?a=thing&b=nuther"
    end
  
    it "should add the host to the url if configured" do
      @server.url_host = 'http://some.server:4000'
      @server.url_for(@job).should == "http://some.server:4000/media/#{@job.serialize}"
    end

    it "should add the host to the url if passed in" do
      @server.url_for(@job, :host => 'https://bungle.com').should == "https://bungle.com/media/#{@job.serialize}"
    end

    it "should favour the passed in host" do
      @server.url_host = 'http://some.server:4000'
      @server.url_for(@job, :host => 'https://smeedy').should == "https://smeedy/media/#{@job.serialize}"
    end
  
    describe "Denial of Service protection" do
      before(:each) do
        @app = test_app
        @server = Dragonfly::Server.new(@app)
        @server.protect_from_dos_attacks = true
        @job = @app.fetch('some_uid')
      end
      it "should generate the correct url" do
        @server.url_for(@job).should == "/#{@job.serialize}?sha=#{@job.sha}"
      end
    end

  end
  
  describe "before_serve callback" do
    
    before(:each) do
      @app = test_app
      @app.generator.add(:test){ "TEST" }
      @server = Dragonfly::Server.new(@app)
      @job = @app.generate(:test)
      @x = x = ""
      @server.before_serve do |job, env|
        x << job.data
      end
    end

    it "should be called before serving" do
      response = request(@server, "/#{@job.serialize}")
      response.body.should == 'TEST'
      @x.should == 'TEST'
    end

    it "should not be called before serving a 404 page" do
      response = request(@server, "blah")
      response.status.should == 404
      @x.should == ""
    end

  end

  describe "after_serve callback" do

    before(:each) do
      @app = test_app
      @app.generator.add(:test){ "TEST" }
      @server = Dragonfly::Server.new(@app)
      @job = @app.generate(:test)
      @x = x = ""
      @server.after_serve do |job, env|
        x << job.data
      end
    end

    it "should be called after serving" do
      response = request(@server, "/#{@job.serialize}")
      response.body.should == 'TEST'
      @x.should == 'TEST'
    end

    it "should not be called after serving a 404 page" do
      response = request(@server, "blah")
      response.status.should == 404
      @x.should == ""
    end

  end

end

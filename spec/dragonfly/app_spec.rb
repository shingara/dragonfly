require 'spec_helper'
require 'rack/mock'

def request(app, path)
  Rack::MockRequest.new(app).get(path)
end

describe Dragonfly::App do

  describe ".instance" do

    it "should create a new instance if it didn't already exist" do
      app = Dragonfly::App.instance(:images)
      app.should be_a(Dragonfly::App)
    end

    it "should return an existing instance if called by name" do
      app = Dragonfly::App.instance(:images)
      Dragonfly::App.instance(:images).should == app
    end

    it "should also work using square brackets" do
      Dragonfly[:images].should == Dragonfly::App.instance(:images)
    end

  end

  describe ".new" do
    it "should not be callable" do
      lambda{
        Dragonfly::App.new
      }.should raise_error(NoMethodError)
    end
  end

  describe "#datastore" do
    let(:app) { test_app }
    context "with no datastore define" do
      it 'should return the default datastore if no define' do
        app.datastore.should be_a Dragonfly::DataStorage::FileDataStore
      end
    end

    context "with a datastore define" do
      before { app.datastore = Dragonfly::DataStorage::S3DataStore.new }
      it 'should return the default datastore define' do
        app.datastore.should be_a Dragonfly::DataStorage::S3DataStore
      end
    end

    context "with alternate_datastore define" do
      before { app.alternate_datastore = {:s3 => Dragonfly::DataStorage::S3DataStore.new } }
      it 'should return the default if not arg pass' do
        app.datastore.should be_a Dragonfly::DataStorage::FileDataStore
      end
      it 'should return the s3 storage if s3 is call' do
        app.datastore(:s3).should be_a Dragonfly::DataStorage::S3DataStore
      end

    end

  end
  describe "#alternate_datastore" do
    let(:app) { test_app }
    context "with no define" do
      it 'should return an empty value' do
        app.alternate_datastore(:fs).should be_nil
      end
    end

    context "with define some alternate_datastore" do
      before { app.alternate_datastore = {:s3 => Dragonfly::DataStorage::S3DataStore.new } }
      it 'should return a datastore if key is define' do
        app.alternate_datastore(:s3).should be_a Dragonfly::DataStorage::S3DataStore
      end
      it 'should return an empty value if key unknow' do
        app.alternate_datastore(:fs).should be_nil
      end
    end
  end

  describe "mime types" do
    describe "#mime_type_for" do
      before(:each) do
        @app = test_app
      end
      it "should return the correct mime type for a symbol" do
        @app.mime_type_for(:png).should == 'image/png'
      end
      it "should work for strings" do
        @app.mime_type_for('png').should == 'image/png'
      end
      it "should work with uppercase strings" do
        @app.mime_type_for('PNG').should == 'image/png'
      end
      it "should work with a dot" do
        @app.mime_type_for('.png').should == 'image/png'
      end
      it "should return nil if not known" do
        @app.mime_type_for(:mark).should be_nil
      end
      it "should allow for configuring extra mime types" do
        @app.register_mime_type 'mark', 'application/mark'
        @app.mime_type_for(:mark).should == 'application/mark'
      end
      it "should override existing mime types when registered" do
        @app.register_mime_type :png, 'ping/pong'
        @app.mime_type_for(:png).should == 'ping/pong'
      end
      it "should have a per-app mime-type configuration" do
        other_app = Dragonfly[:other_app]
        @app.register_mime_type(:mark, 'first/one')
        other_app.register_mime_type(:mark, 'second/one')
        @app.mime_type_for(:mark).should == 'first/one'
        other_app.mime_type_for(:mark).should == 'second/one'
      end
    end
  end

  describe "remote_url_for" do
    let(:app) { test_app }
    before(:each) do
      app.datastore = Object.new
    end
    it "should raise an error if the datastore doesn't provide it" do
      lambda{
        app.remote_url_for('some_uid')
      }.should raise_error(NotImplementedError)
    end
    it "should correctly call it if the datastore provides it" do
      app.datastore.should_receive(:url_for).with('some_uid', :some => :opts).and_return 'http://egg.head'
      app.remote_url_for('some_uid', :some => :opts).should == 'http://egg.head'
    end
    context "with alternate datastore define" do
      let(:second_datastore) { Dragonfly::DataStorage::FileDataStore.new }
      before { app.alternate_datastore = {:second => second_datastore} }
      it 'should use the second datastore if :datastore option is pass' do
        app.datastore(:second).should_receive(:url_for).with('some_uid', :some => :opts).and_return 'http://egg.head'
        app.remote_url_for('some_uid', :some => :opts, :datastore => :second).should == 'http://egg.head'
      end
    end
  end

  describe "#store" do
    let(:app) { test_app }
    it "should allow just storing content" do
      app.datastore.should_receive(:store).with(a_temp_object_with_data("HELLO"), {})
      app.store("HELLO")
    end
    it "should allow storing using a TempObject" do
      temp_object = Dragonfly::TempObject.new("HELLO")
      app.datastore.should_receive(:store).with(temp_object, {})
      app.store(temp_object)
    end
    it "should allow storing with extra stuff" do
      app.datastore.should_receive(:store).with(
        a_temp_object_with_data("HELLO"), :meta => {:egg => :head}, :option => :blarney
      )
      app.store("HELLO", :meta => {:egg => :head}, :option => :blarney)
    end
    context "with alternate datastore define" do
      let(:second_datastore) { Dragonfly::DataStorage::FileDataStore.new }
      before { app.alternate_datastore = {:second => second_datastore} }
      it 'should use the second datastore if :datastore option is pass' do
        temp_object = Dragonfly::TempObject.new("HELLO")
        app.datastore(:second).should_receive(:store).with(temp_object, {})
        app.store(temp_object, :datastore => :second)
      end
    end
  end

  describe "url_for" do
    before(:each) do
      @app = test_app
      @job = @app.fetch('eggs')
    end
    it "should give the server url by default" do
      @app.url_for(@job).should =~ %r{^/\w+$}
    end
    it "should allow configuring" do
      @app.configure do |c|
        c.define_url do |app, job, opts|
          "doogies"
        end
      end
      @app.url_for(@job).should == 'doogies'
    end
    it "should yield the correct dooberries" do
      @app.define_url do |app, job, opts|
        [app, job, opts]
      end
      @app.url_for(@job, {'chuddies' => 'margate'}).should == [@app, @job, {'chuddies' => 'margate'}]
    end
  end

  describe "reflection methods" do
    before(:each) do
      @app = test_app.configure do |c|
        c.processor.add(:milk){}
        c.generator.add(:butter){}
        c.analyser.add(:cheese){}
        c.job(:bacon){}
      end

    end
    it "should return processor methods" do
      @app.processor_methods.should == [:milk]
    end
    it "should return generator methods" do
      @app.generator_methods.should == [:butter]
    end
    it "should return analyser methods" do
      @app.analyser_methods.should == [:cheese]
    end
    it "should return job methods" do
      @app.job_methods.should == [:bacon]
    end
  end

end

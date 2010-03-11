$:.unshift *Dir[File.dirname(__FILE__) + "/vendor/*/lib"]
require 'rubygems'
require 'sinatra'
require 'logger'
require 'active_record'
require 'delayed_job'
require 'rack/conneg'
load 'lib/util.rb'
include RDFObject
unless ENV['PLATFORM_STORE']
  CONFIG = YAML.load_file('config/config.yml')
end
RELATORS = {:missing=>[]}
RELATORS[:codes] = YAML.load_file('lib/relators.yml')
STORE = Pho::Store.new(ENV['PLATFORM_STORE'] || CONFIG['store']['uri'], 
  ENV['PLATFORM_USERNAME'] || CONFIG['store']['username'],
  ENV['PLATFORM_PASSWORD'] || CONFIG['store']['password'])

configure do
  Curie.add_prefixes! :mo=>"http://purl.org/ontology/mo/", :skos=>"http://www.w3.org/2004/02/skos/core#",
   :owl=>'http://www.w3.org/2002/07/owl#', :wgs84 => 'http://www.w3.org/2003/01/geo/wgs84_pos#', 
   :dcterms => 'http://purl.org/dc/terms/', :bibo => 'http://purl.org/ontology/bibo/', :rda=>"http://RDVocab.info/Elements/",
   :role => 'http://RDVocab.info/roles/', :umbel => 'http://umbel.org/umbel#', :meta=>"http://purl.org/NET/lccn/vocab/",
   :rss => "http://purl.org/rss/1.0/"

  dbconf = CONFIG['database']
  ActiveRecord::Base.establish_connection(dbconf) 
  ActiveRecord::Base.logger = Logger.new(File.open('log/database.log', 'a')) 
  ActiveRecord::Migrator.up('db/migrate')
end

use(Rack::Conneg) { |conneg|
  conneg.set :accept_all_extensions, false
  conneg.set :fallback, :html
  conneg.ignore('/public/')
  conneg.ignore('/css/')
  conneg.ignore('/js/')
  conneg.provide([:rdf, :txt, :html])
}

before do  
  content_type negotiated_type
end

layout do
  IO.read("views/layout.haml")
end

get '/:id' do
  @resource = fetch_resource("http://purl.org/NET/lccn/#{params[:id]}#i")
  not_found if @resource.empty_graph?
  respond_to do | wants |
    wants.html { haml :lccn }
    wants.rdf { @resource.to_xml(2) }
    wants.txt { @resource.to_ntriples }
  end  
end

get '/subjects/:label' do
  @resource = fetch_resource("http://purl.org/NET/lccn/subjects/#{CGI.escape(params[:label])}#concept")
  not_found if @resource.empty_graph?
  respond_to do | wants |
    wants.html { haml :lccn }
    wants.rdf { @resource.to_xml(2) }
    wants.txt { @resource.to_ntriples }
  end
end

get '/people/:id' do
  @resource = fetch_resource("http://purl.org/NET/lccn/people/#{params[:id]}#i")
  not_found if @resource.empty_graph?
  respond_to do | wants |
    wants.html { haml :lccn }
    wants.rdf { @resource.to_xml(2) }
    wants.txt { @resource.to_ntriples }
  end 
end

get '/log/jobs' do
  @jobs = Delayed::Job.find(:all)
  haml :job_status, :layout=>:job
end

get '/missing/relators' do
  content_type 'application/json', :charset => 'utf-8'
  RELATORS[:missing].to_json
end

helpers do
  def curied_uri(uri)
    curie = Curie.create_from_uri(uri)
    return "#{curie.prefix}:#{curie.reference}"
  end
  
  def find_title(resource)
    if resource.rda && resource.rda['titleProper']
      return [*resource.rda['titleProper']].first
    elsif resource.skos && resource.skos['prefLabel']
      return [*resource.skos['prefLabel']].first
    elsif resource.foaf && resource.foaf['name']
      return [*resource.foaf['name']].first
    elsif resource.dcterms && resource.dcterms['title']
      return [*resource.dcterms['title']].first
    else
      "Unknown title"
    end
  end
  
  def display_class(resource)
    if resource.rdf && resource.rdf['type']
      [*resource.rdf['type']].each do |rdf_type|
        display_type = case rdf_type.uri
        when "http://purl.org/ontology/bibo/Book" then "biboBook"
        when "http://purl.org/ontology/bibo/Journal" then "biboJournal"
        when "http://xmlns.com/foaf/0.1/Person" then "foafPerson"
      
        else nil
        end
        return display_type if display_type
      end
    end
    "Generic"
  end
end
not_found do
  "Resource not found"
end


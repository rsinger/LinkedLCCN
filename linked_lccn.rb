require 'rubygems'
require 'sinatra'
load 'lib/util.rb'
load 'lib/lookups.rb'
load 'lib/marc_methods.rb'
include RDFObject

configure do
  Curie.add_prefixes! :mo=>"http://purl.org/ontology/mo/", :skos=>"http://www.w3.org/2004/02/skos/core#",
   :owl=>'http://www.w3.org/2002/07/owl#', :wgs84 => 'http://www.w3.org/2003/01/geo/wgs84_pos#', 
   :dcterms => 'http://purl.org/dc/terms/', :bibo => 'http://purl.org/ontology/bibo/', :rda=>"http://RDVocab.info/Elements/",
   :role => 'http://RDVocab.info/roles/', :umbel => 'http://umbel.org/umbel#', :meta=>"http://purl.org/NET/lccn/vocab/",
   :rss => "http://purl.org/rss/1.0/"
  unless ENV['PLATFORM_STORE']
    config = YAML.load_file('config/config.yml')
  end
  RELATORS = {:missing=>[]}
  RELATORS[:codes] = YAML.load_file('lib/relators.yml')
  STORE = Pho::Store.new(ENV['PLATFORM_STORE'] || config['store']['uri'], 
    ENV['PLATFORM_USERNAME'] || config['store']['username'],
    ENV['PLATFORM_PASSWORD'] || config['store']['password'])
end
get '/:id' do
  resource = fetch_resource("http://purl.org/NET/lccn/#{params[:id]}#i")
  not_found if resource.empty_graph?
  content_type 'application/rdf+xml', :charset => 'utf-8'
  headers['Cache-Control'] = 'public, max-age=21600'
  resource.to_xml(2)
end

get '/subjects/:label' do
  concept = fetch_resource("http://purl.org/NET/lccn/subjects/#{CGI.escape(params[:label])}#concept")
  not_found if concept.empty_graph?
  content_type 'application/rdf+xml', :charset => 'utf-8'  
  concept.to_xml(2)
end

get '/people/:id' do
  person = fetch_resource("http://purl.org/NET/lccn/people/#{params[:id]}#i")
  not_found if person.empty_graph?
  content_type 'application/rdf+xml', :charset => 'utf-8'  
  person.to_xml(2)  
end

get '/missing/relators' do
  content_type 'application/json', :charset => 'utf-8'
  RELATORS[:missing].to_json
end

not_found do
  "Resource not found"
end

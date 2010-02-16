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
   :role => 'http://RDVocab.info/roles/', :umbel => 'http://umbel.org/umbel#'
  RELATORS = {:missing=>[]}
  RELATORS[:codes] = YAML.load_file('lib/relators.yml')
end
get '/:id' do
  marc = get_marc(params["id"])
  not_found if marc.nil?
  rdf = to_rdf(marc)
  content_type 'application/rdf+xml', :charset => 'utf-8'
  headers['Cache-Control'] = 'public, max-age=21600'  
  #to_rdfxml(rdf)
  rdf.to_xml(2)
end

get '/subjects/:label' do
  concept = Resource.new("http://purl.org/NET/lccn/subjects/#{CGI.escape(params[:label])}")
  concept.relate("[rdf:type]", "[skos:Concept]")
  concept.assert("[skos:prefLabel]", params[:label])
  content_type 'application/rdf+xml', :charset => 'utf-8'  
  concept.to_xml(2)
end

get '/people/:id' do
  person = viaf_by_id(params[:id])
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

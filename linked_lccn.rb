require 'rubygems'
require 'sinatra'
require 'haml'

require 'rack/conneg'
load 'lib/util.rb'


configure do
  init_environment

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


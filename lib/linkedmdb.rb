class LinkedLCCN::LinkedMDB
  def self.lookup(title)

  sparql = <<SPARQL
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX movie: <http://data.linkedmdb.org/resource/movie/>
PREFIX dc: <http://purl.org/dc/terms/>
DESCRIBE * WHERE {
 ?obj rdf:type movie:film .
 ?obj dc:title ?title FILTER regex(?title, "^#{title}$", "i" )
}
SPARQL
    uri = "http://data.linkedmdb.org/sparql?query=#{CGI.escape(sparql)}"
    begin
      response = RDFObject::HTTPClient.fetch(uri)
      collection = RDFObject::XMLParser.parse response[:content]
    rescue 
      return nil
    end
    return nil if collection.empty?
    resources = collection.find_by_predicate("[rdf:type]")
    resources.each do | r |
      break unless r.is_a?(Array)
      r.each do | resource |
        next unless resource.is_a?(RDFObject::Resource)
        [*resource['[rdf:type]']].each do | type |
          return resource if type.uri == "http://data.linkedmdb.org/resource/movie/film"
        end
      end
    end
    nil
  end
end  
class LinkedLCCN::DBpedia
  def self.film_lookup(title)

  sparql = <<SPARQL
PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
DESCRIBE * WHERE {
?obj rdf:type <http://dbpedia.org/ontology/Film> .
?obj foaf:name ?title FILTER regex(?title, "^#{title}$", "i" )
}
SPARQL
    uri = "http://dbpedia.org/sparql?query=#{CGI.escape(sparql)}"
    response = RDFObject::HTTPClient.fetch(uri)
    collection = RDFObject::XMLParser.parse response[:content]
    return nil if collection.empty?
    resources = collection.find_by_predicate("[rdf:type]")
    resources.each do | r |
      break unless r.is_a?(Array)
      r.each do | resource |
        next unless resource.is_a?(RDFObject::Resource)
        [*resource['[rdf:type]']].each do | type |
          return resource if type.uri == "http://dbpedia.org/ontology/Film"
        end
      end
    end
    nil
  end  

  def self.journal_lookup(title, issn)

  sparql = <<SPARQL
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
PREFIX dbpedia: <http://dbpedia.org/property/>
DESCRIBE * WHERE {
?obj dbpedia:issn ?issn FILTER regex(?issn, "#{issn}", "i") .
?obj rdfs:label ?title FILTER regex(?title, "^#{title}$", "i" )
}
SPARQL
    uri = "http://dbpedia.org/sparql?query=#{CGI.escape(sparql)}"
    response = RDFObject::HTTPClient.fetch(uri)
    collection = RDFObject::XMLParser.parse response[:content]
    return nil if collection.empty?
    resources = collection.find_by_predicate("http://dbpedia.org/property/issn")
    resources.each do | r |
      break unless r.is_a?(Array)
      r.each do | resource |
        next unless resource.is_a?(RDFObject::Resource)
        return resource
      end
    end
    nil
  end
  
end
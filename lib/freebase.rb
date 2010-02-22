require 'ken'
class LinkedLCCN::Freebase
  def self.book_lookup(title, author)
    fuzz_auth = author['a'].split(",")[0]
    resources = Ken.all(:name=>title, :"author~="=>fuzz_auth, :type=>"/book/written_work")
    matched_resource = nil
    resources.each do | resource |
      if resources.length == 1
        matched_resource = resource
        break
      end
    end
    if matched_resource
      r = RDFObject::Resource.new("http://rdf.freebase.com/ns/#{matched_resource.id.sub(/^\//,"").gsub(/\//,".")}")
      return r
    else
      return nil
    end
  end  

  def self.journal_lookup(title, issn=nil)
    resources = Ken.all(:name=>title, :ISSN=>issn, :type=>"/book/periodical")
    matched_resource = nil
    resources.each do | resource |
      if resources.length == 1
        matched_resource = resource
        break
      end
    end
    if matched_resource
      r = RDFObject::Resource.new("http://rdf.freebase.com/ns/#{matched_resource.id.sub(/^\//,"").gsub(/\//,".")}")
      return r
    else
      return nil
    end
  end 
   
  def self.film_lookup(title, year=nil)
    resources = Ken.all(:name=>title, :"author~="=>fuzz_auth, :type=>"/film/film")
    matched_resource = nil
    resources.each do | resource |
      if resources.length == 1
        matched_resource = resource
        break
      end
    end
    if matched_resource
      r = RDFObject::Resource.new("http://rdf.freebase.com/ns/#{matched_resource.id.sub(/^\//,"").gsub(/\//,".")}")
      return r
    else
      return nil
    end
  end   
end
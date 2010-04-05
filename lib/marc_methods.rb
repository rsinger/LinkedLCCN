module LinkedLCCN
  module SoundResource
    def model_resource(marc, resource)
      resource.relate("[rdf:type]", "[mo:Recording]")
      upcs = marc.find_all {|f| f.tag == "024"}
      mbrainz_params = {:title=>marc['245']['a']}
      mbrainz_params[:artist] = case
      when marc['100'] then marc['100']['a']
      when marc['110'] then marc['110']['a']
      when marc['111'] then marc['111']['a']
      when marc['700'] then marc['700']['a']
      when marc['710'] then marc['710']['a']
      end
      mbrainz = {}
      unless upcs.empty?
        upcs.each do | upc |
          next unless upc.indicator1 == "1"
          resource.assert("[mo:barcode]", upc['a'])
          mbrainz_params[:barcode] ||=[]
          mbrainz_params[:barcode] << upc['a']
        end
      end
      cat_nums = marc.find_all {|f| f.tag == "028"}
      cat_nums.each do | cat_num |
        if cat_num['a']
          resource.assert("[mo:catalogue_number]", cat_num['a'])
          mbrainz_params[:catno] ||=[]
          mbrainz_params[:catno] << cat_num['a']
        end
        if cat_num['b']
          mbrainz_params[:label] ||=[]
          mbrainz_params[:label] << cat_num['b']
        end
      end

      if mbrainz = LinkedLCCN::MusicBrainz.lookup(mbrainz_params)
        if mbrainz[:release]
          mbrainz[:release].each do | r |
            resource.relate("[owl:sameAs]", r)
          end
        end
        if mbrainz[:record]
          mbrainz[:record].each do | r |
            resource.relate("[dcterms:isVersionOf]", r)
          end
        end
        if mbrainz[:tracks]
          mbrainz[:tracks].each do | t |
            resource.relate("[mo:track]", t)
          end
        end
        if mbrainz[:labels]
          mbrainz[:labels].each do | l |
            resource.relate("[mo:label]", l)
          end
        end
      end
    end
  end

  module BookResource
    def model_resource(marc, resource)

      if marc.is_conference?
        resource.relate("[rdf:type]","[bibo:Proceedings]")
      elsif marc.is_manuscript?
        resource.relate("[rdf:type]","[bibo:Manuscript]")
      elsif marc.nature_of_contents && marc.nature_of_contents.index("m")
        resource.relate("[rdf:type]","[bibo:Thesis]")
      elsif marc.nature_of_contents && marc.nature_of_contents.index("u")
        resource.relate("[rdf:type]","[bibo:Standard]")
      elsif marc.nature_of_contents && marc.nature_of_contents.index("j")
        resource.relate("[rdf:type]","[bibo:Patent]")    
      elsif marc.nature_of_contents && marc.nature_of_contents.index("t")
        resource.relate("[rdf:type]","[bibo:Report]")
      elsif marc.nature_of_contents && marc.nature_of_contents.index("l")
        resource.relate("[rdf:type]","[bibo:Legislation]")
      elsif marc.nature_of_contents && marc.nature_of_contents.index("v")
        resource.relate("[rdf:type]","[bibo:LegalCaseDocument]")
      elsif marc.nature_of_contents && !(marc.nature_of_contents & ["d", "e", "r"]).empty?
        resource.relate("[rdf:type]","[bibo:ReferenceSource]")
      else
        resource.relate("[rdf:type]", "[bibo:Book]")
      end

      if marc.nature_of_contents(true)
        marc.nature_of_contents(true).each do | genre |        
          resource.assert("[dcterms:type]", genre)
        end
      end

      if ol = LinkedLCCN::OpenLibrary.lookup(marc['010'].value.strip)
        resource.relate("[owl:sameAs]", "http://openlibrary.org#{ol.first['key']}")
      end

      freebase = case
      when marc['100'] then LinkedLCCN::Freebase.book_lookup(marc['245']['a'].strip_trailing_punct, marc['100'])
      when marc['111'] then LinkedLCCN::Freebase.book_lookup(marc['245']['a'].strip_trailing_punct, marc['110'])
      else nil
      end
      if freebase
        resource.relate("[dcterms:isVersionOf]", freebase)
      end            
    end
  end
  
  module SerialResource

    def model_resource(marc, resource)
      if marc.nature_of_contents
        marc.nature_of_contents(true).each do | genre |        
          resource.assert("[dcterms:type]", genre)
        end
      end
      type = marc.serial_type(true)
      if type == 'Newspaper'
        resource.relate("[rdf:type]","[bibo:Newspaper]")
      elsif type == 'Website'
        resource.relate("[rdf:type]","[bibo:Website]") 
      elsif type == 'Periodical'    
        if marc['245'].to_s =~ /\bjournal\b/i
          resource.relate("[rdf:type]","[bibo:Journal]")
        elsif marc['245'].to_s =~ /\bmagazine\b/i
          resource.relate("[rdf:type]","[bibo:Magazine]")
        else
         resource.relate("[rdf:type]","[bibo:Periodical]")
        end
      end
      if marc['022']
        issn = marc['022']['a'].gsub(/[^0-9{4}\-?0-9{3}0-9Xx]/,"") if marc['022']['a']
        unless issn.empty?
          periodical = Resource.new("http://periodicals.dataincubator.org/issn/#{issn}") 
          begin
            periodical.describe
            if periodical.owl && periodical.owl['sameAs']
              [*periodical.owl['sameAs']].each do | same_as |
                resource.assert("[owl:sameAs]", same_as)
              end
            end
          rescue RuntimeError
          end
        end
        if freebase = LinkedLCCN::Freebase.journal_lookup(marc['245']['a'].strip_trailing_punct, issn)
          resource.assert("[owl:sameAs]", freebase)
        end
        if dbpedia = LinkedLCCN::DBpedia.journal_lookup(marc['245']['a'].strip_trailing_punct, issn)
          resource.assert("[owl:sameAs]", dbpedia)
        end    
      end
    end
    if @lccn =~ /^sn/
      if chronam = LinkedLCCN::LibraryOfCongress.lookup_chronam(@lccn)
        resource.assert("[owl:sameAs]", chronam)
      end
    end    
  end
  
  module MapResource
    def model_resource(marc, resource)
      resource.relate("[rdf:type]", "[bibo:Map]")
      cart = marc.find_all {|f| f.tag == "034"}
      cart.each do | c |
        if c['d'] and c['e'] and c['f'] and c['g']
          west = coordinate_to_decimal(c['d'])
          east = coordinate_to_decimal(c['e'])      
          north = coordinate_to_decimal(c['f'])
          south = coordinate_to_decimal(c['g'])
          resource.assert("http://www.georss.org/georss#box", "#{south} #{west} #{north} #{east}")
        end
      end
    end

    def coordinate_to_decimal(coordinate)
      return coordinate if coordinate =~ /\-?[0-9]{3}\.[0-9]*/
      decimal = nil
      if coordinate !~ /\./
        decimal = coordinate.sub(/^[SW]/,"-").sub(/^[NE]/,"")
        decimal.sub!(/([0-9]{3})/,'\1.')
      end
      if decimal && decimal =~ /\.[0-9]{4}/
        minsec = decimal.match(/\.([0-9]{2})([0-9]{2})/)
        minute = (minsec[1].to_i/60)
        second = (minsec[2].to_i/3600)
        (degree, mmss) = decimal.split(/\./)
        decimal = "#{degree}.#{minute}#{second}"
      end
      return decimal
    end
  end
  
  module VisualResource
    def model_resource(marc, resource)
      type = marc.material_type(true)
      if (type == "Videorecording" or type == "Motion picture") or (marc['245'] && marc['245']['h'] && marc['245']['h'] =~ /videorecording/)
        resource.relate("[rdf:type]","[bibo:Film]")
        if linkedmdb = LinkedLCCN::LinkedMDB.lookup(marc['245']['a'].strip_trailing_punct)
          resource.relate("[dcterms:isVersionOf]", linkedmdb)
        elsif dbpedia = LinkedLCCN::DBpedia.film_lookup(marc['245']['a'].strip_trailing_punct)
          resource.relate("[dcterms:isVersionOf]", dbpedia)
        end
      elsif type
        resource.assert("[dct:type]", type)
      end  
    end    
  end
  
  module GenericResource
    def model_resource(marc, resource)
    end
  end
end
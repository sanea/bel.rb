module BEL::Translator::Plugins

  module Ntriples

    ID          = :ntriples
    NAME        = 'N-triples RDF Translator'
    DESCRIPTION = 'A translator that can read and write N-triples for BEL evidence.'
    MEDIA_TYPES = %i(application/n-triples)
    EXTENSIONS  = %i(nt)

    def self.create_translator(options = {})
      require_relative 'rdf/translator'
      BEL::Translator::Plugins::Rdf::RdfTranslator.new(ID)
    end

    def self.id
      ID
    end

    def self.name
      NAME
    end

    def self.description
      DESCRIPTION
    end

    def self.media_types
      MEDIA_TYPES
    end 

    def self.file_extensions
      EXTENSIONS
    end
  end
end
require_relative 'bel_citation_serialization'
require_relative 'bel_discrete_serialization'
require_relative 'bel_top_down_serialization'
require 'bel'

module BEL::Translator::Plugins

  module BelScript

    class BelYielder

      # Create a {BelYielder} object that serializes {BEL::Model::Evidence} to
      # BEL Script.
      #
      # @param [Enumerator<BEL::Model::Evidence>] data evidence data iterated
      #        using +each+
      # @option options [Boolean] :write_header +true+ to write the BEL Script
      #         document header; +false+ to not write the BEL Script document
      #         header
      # @option options [Symbol,Module] :serialization the serialization
      #         technique to use for evidence; a +Module+ type will be used as
      #         is; a +Symbol+ type will be mapped as
      #         +:discrete+ => {BelDiscreteSerialization},
      #         +:topdown+ => {BelTopDownSerialization},
      #         +:citation+ => {BelCitationSerialization}; otherwise the default
      #         of {BelCitationSerialization} is used
      def initialize(data, options = {})
        @data                     = data
        @streaming                = options.fetch(:streaming, false)
        @write_header             = options.fetch(:write_header, true)
        @annotation_reference_map = options.fetch(:annotation_reference_map, nil)
        @namespace_reference_map  = options.fetch(:namespace_reference_map, nil)

        # augment self with BEL serialization stategy.
        serialization = options[:serialization]
        serialization_module =
          case serialization
          when Module
            serialization
          when String, Symbol
            serialization_refs = {
              :discrete => BelDiscreteSerialization,
              :topdown  => BelTopDownSerialization,
              :citation => BelCitationSerialization,
            }
            serialization_module = serialization_refs[serialization.to_sym]
            unless serialization_module
                raise %Q{No BEL serialization strategy for "#{serialization}"}
            end
            serialization_module
          else
            # Default to citation serialization.
            BelCitationSerialization
          end

        self_eigenclass = (class << self; self; end)
        self_eigenclass.send(:include, serialization_module)
      end

      def each
        if block_given?
          combiner =
            if @streaming
              BEL::Model::StreamingEvidenceCombiner.new(@data)
            elsif @annotation_reference_map && @namespace_reference_map
              BEL::Model::MapReferencesCombiner.new(
                @data,
                BEL::Model::HashMapReferences.new(
                  @annotation_reference_map,
                  @namespace_reference_map
                )
              )
            else
              BEL::Model::BufferingEvidenceCombiner.new(@data)
            end

          header_flag = true
          combiner.each { |evidence|

            # serialize evidence
            bel = to_bel(evidence)

            if @write_header && header_flag
              yield document_header(evidence.metadata.document_header)
              yield namespaces(combiner.namespace_references)
              yield annotations(combiner.annotation_references)

              yield <<-COMMENT.gsub(/^\s+/, '')
                ###############################################
                # Statements Section
              COMMENT
              header_flag = false
            end

            yield bel
          }

          yield epilogue
        else
          to_enum(:each)
        end
      end

      private

      def document_header(header)
        return "" unless header

        bel = <<-COMMENT.gsub(/^\s+/, '')
          ###############################################
          # Document Properties Section
        COMMENT

        header.each { |name, value|
          name_s  = name.to_s
          value_s =
            if value.respond_to?(:each)
              value.join('|')
            else
              value.to_s
            end

          # handle casing for document properties (special case, contactinfo)
          name_s = (name_s.downcase == 'contactinfo') ?
            'ContactInfo' :
            name_s.capitalize

          bel << %Q{SET DOCUMENT #{name_s} = "#{value_s}"\n}
        }

        bel << "\n"
        bel
      end

      def annotations(annotation_references)
        bel = <<-COMMENT.gsub(/^\s+/, '')
          ###############################################
          # Annotation Definitions Section
        COMMENT

        return bel unless annotation_references

        annotation_references.reduce(bel) { |bel, ref|
          keyword, type, domain = ref.values_at(:keyword, :type, :domain)
          bel << "DEFINE ANNOTATION #{keyword} AS "

          case type.to_sym
          when :uri
            bel << %Q{URL "#{domain}"\n}
          when :pattern
            regex = domain.respond_to?(:source) ? domain.source : domain
            bel << %Q{PATTERN "#{regex}"\n}
          when :list
            bel << %Q|LIST {#{domain.inspect[1...-1]}}\n|
          end
          bel
        }
        bel << "\n"
        bel
      end

      def namespaces(namespace_references)
        bel = <<-COMMENT.gsub(/^\s+/, '')
          ###############################################
          # Namespace Definitions Section
        COMMENT

        return bel unless namespace_references

        namespace_references.reduce(bel) { |bel, ref|
          keyword, url = ref.values_at(:keyword, :uri)
          bel << %Q{DEFINE NAMESPACE #{keyword} AS URL "#{url}"\n}
          bel
        }
        bel << "\n"
        bel
      end
    end
  end
end

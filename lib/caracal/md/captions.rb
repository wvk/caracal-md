module Caracal
  module Md
    # Numbered captions and cross-references, shared by Converter and
    # PostProcessor: the label and SEQ field name of each kind, the titles of
    # the lists of figures and tables, and the references the converter emits
    # as ref:N markers.
    class Captions
      KINDS = %i[figure table].freeze

      LABELS = {
        'en' => { figure: 'Figure',    table: 'Table' },
        'de' => { figure: 'Abbildung', table: 'Tabelle' },
        'fr' => { figure: 'Figure',    table: 'Tableau' },
        'nl' => { figure: 'Figuur',    table: 'Tabel' },
        'es' => { figure: 'Figura',    table: 'Tabla' },
        'it' => { figure: 'Figura',    table: 'Tabella' },
      }.freeze

      LIST_TITLES = {
        'en' => { figure: 'List of Figures',     table: 'List of Tables' },
        'de' => { figure: 'Abbildungsverzeichnis', table: 'Tabellenverzeichnis' },
        'fr' => { figure: 'Table des figures',   table: 'Liste des tableaux' },
        'nl' => { figure: 'Lijst van figuren',   table: 'Lijst van tabellen' },
        'es' => { figure: 'Índice de figuras',   table: 'Índice de tablas' },
        'it' => { figure: 'Indice delle figure', table: 'Indice delle tabelle' },
      }.freeze

      # The SEQ field that counts level-1 headings in chapter mode.
      CHAPTER_SEQUENCE = 'Chapter'.freeze

      attr_reader :references

      # +mode+: false numbers the captions of figures and tables with an id,
      # true every caption, :chapter every caption per level-1 heading
      # ("Figure 2.1"). +labels+ and +list_titles+ ({ figure:, table: })
      # replace the ones for +lang+.
      def initialize(mode: false, lang: nil, labels: {}, list_titles: {})
        lang = lang.to_s[0, 2]
        @mode        = (mode.to_s == 'chapter') ? :chapter : (mode ? true : false)
        @labels      = LABELS.fetch(lang, LABELS['en']).merge(compact(labels))
        @list_titles = LIST_TITLES.fetch(lang, LIST_TITLES['en']).merge(compact(list_titles))
        @references  = []
      end

      def number_all?
        @mode != false
      end

      def chapters?
        @mode == :chapter
      end

      def label(kind)
        @labels.fetch(kind)
      end

      def list_title(kind)
        @list_titles.fetch(kind)
      end

      # The SEQ field name: the label's letters, digits and underscores,
      # starting with a letter.
      def sequence(kind)
        name = label(kind).gsub(/[^\p{L}\p{N}_]/, '')
        name.match?(/\A\p{L}/) ? name[0, 40] : LABELS['en'].fetch(kind)
      end

      # Registers a reference to the bookmark +bookmark+ and returns its
      # number for the ref marker. +source+ is shown when the bookmark is
      # missing.
      def reference(bookmark, source)
        @references << { bookmark: bookmark, source: source }
        @references.size - 1
      end

      private

      def compact(hash)
        hash.to_h.reject { |_, value| value.to_s.strip.empty? }.transform_values(&:to_s)
      end
    end
  end
end

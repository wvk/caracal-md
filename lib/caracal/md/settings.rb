module Caracal
  module Md
    # Inserts elements into word/settings.xml at their schema position
    # (CT_Settings is a sequence, so Word rejects elements out of order).
    module Settings
      ORDER = %w[
        writeProtection view zoom removePersonalInformation removeDateAndTime doNotDisplayPageBoundaries
        displayBackgroundShape printPostScriptOverText printFractionalCharacterWidth printFormsData
        embedTrueTypeFonts embedSystemFonts saveSubsetFonts saveFormsData mirrorMargins alignBordersAndEdges
        bordersDoNotSurroundHeader bordersDoNotSurroundFooter gutterAtTop hideSpellingErrors hideGrammaticalErrors
        activeWritingStyle proofState formsDesign attachedTemplate linkStyles stylePaneFormatFilter
        stylePaneSortMethod documentType mailMerge revisionView trackRevisions doNotTrackMoves
        doNotTrackFormatting documentProtection autoFormatOverride styleLockTheme styleLockQFSet defaultTabStop
        autoHyphenation consecutiveHyphenLimit hyphenationZone doNotHyphenateCaps showEnvelope summaryLength
        clickAndTypeStyle defaultTableStyle evenAndOddHeaders bookFoldRevPrinting bookFold bookFoldPrinting
        drawingGridHorizontalSpacing drawingGridVerticalSpacing displayHorizontalDrawingGridEvery
        displayVerticalDrawingGridEvery doNotUseMarginsForDrawingGridOrigin drawingGridHorizontalOrigin
        drawingGridVerticalOrigin doNotShadeFormData noPunctuationKerning characterSpacingControl printTwoOnOne
        strictFirstAndLastChars noLineBreaksAfter noLineBreaksBefore savePreviewPicture doNotValidateAgainstSchema
        saveInvalidXml ignoreMixedContent alwaysShowPlaceholderText doNotDemarcateInvalidXml saveXmlDataOnly
        useXSLTWhenSaving saveThroughXslt showXMLTags alwaysMergeEmptyNamespace updateFields hdrShapeDefaults
        footnotePr endnotePr compat docVars rsids mathPr attachedSchema themeFontLang clrSchemeMapping
        doNotIncludeSubdocsInStats doNotAutoCompressPictures forceUpgrade captions readModeInkLockDown smartTagType
        schemaLibrary shapeDefaults doNotEmbedSmartTags decimalSymbol listSeparator
      ].freeze

      # Adds +xml+ (an element named +name+) unless the settings have one.
      def self.ensure(doc, name, xml)
        w = Package::NS['w']
        root = doc.root
        return if root.element_children.any? { |el| el.name == name and el.namespace&.href == w }

        later = ORDER.drop(ORDER.index(name) + 1)
        anchor = root.element_children.find { |el| el.namespace&.href == w and later.include?(el.name) }
        anchor ? anchor.add_previous_sibling(xml) : root.add_child(xml)
      end
    end
  end
end

(import 'shared/default_format.jsonnet') + {
  document_type: 'multi_part',
  definitions: (import 'shared/definitions/_multi_part.jsonnet') + {
    details: {
      type: 'object',
      required: [
        'body',
        'parts',
      ],
      properties: {
        attachments: {
          description: 'An ordered list of asset links',
          type: 'array',
          items: {
            '$ref': '#/definitions/file_attachment_asset',
          },
        },
        body: {
          '$ref': '#/definitions/body',
        },
        parts: {
          type: 'array',
          items: {
            '$ref': '#/definitions/part',
          },
        },
      },
    },
  },
  links: (import 'shared/base_links.jsonnet') + {
    government: {
      description: 'The government associated with this document',
      maxItems: 1,
    },
    primary_publishing_organisation: {
      description: "The organisation that published the page. Corresponds to the first of the 'Lead organisations' in Whitehall, and is empty for all other publishing applications.",
      maxItems: 1,
    },
  },
  edition_links: (import "shared/base_edition_links.jsonnet") + {
    government: {
      description: "The government associated with this document",
      maxItems: 1,
    },
    primary_publishing_organisation: {
      description: "The organisation that published the page. Corresponds to the first of the 'Lead organisations' in Whitehall, and is empty for all other publishing applications.",
      maxItems: 1,
    }
  }
}

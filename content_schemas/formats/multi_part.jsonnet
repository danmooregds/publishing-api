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
        primary_publishing_organisation: {
          '$ref': '#/definitions/emphasised_organisations',
        },
      },
    },
  },
  links: (import 'shared/base_links.jsonnet') + {
    government: {
      description: 'The government associated with this document',
      maxItems: 1,
    },
  },
}

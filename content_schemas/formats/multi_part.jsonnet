(import "shared/default_format.jsonnet") + {
  document_type: 'multi_part',
  definitions: (import 'shared/definitions/_multi_part.jsonnet') + {
    details: {
      type: 'object',
      additionalProperties: false,
      required: [
        'body',
        'parts',
      ],
      properties: {
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
}

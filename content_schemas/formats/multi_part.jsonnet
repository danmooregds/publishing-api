(import "shared/default_format.jsonnet") + {
  document_type: "multi_part",
  definitions: {
    details: {
      type: "object",
      additionalProperties: false,
      required: [
        "body",
      ],
      properties: {
        body: {
          "$ref": "#/definitions/body",
        },
      },
    },
  },
}

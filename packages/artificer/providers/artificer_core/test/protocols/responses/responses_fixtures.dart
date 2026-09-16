Map<String, Object?> responseFixture() => {
  'id': 'r1',
  'model': 'm',
  'status': 'completed',
  'unknown': {
    'deep': [1, null],
  },
  'usage': {'input_tokens': 3, 'output_tokens': 5, 'cache_tokens': 2},
  'output': [
    {
      'type': 'message',
      'id': 'msg',
      'phase': 'final_answer',
      'content': [
        {
          'type': 'output_text',
          'text': 'hello',
          'annotations': [
            {'type': 'url_citation', 'url': 'https://example.test', 'unknown': 9},
          ],
        },
      ],
    },
    {
      'type': 'reasoning',
      'id': 'reason',
      'encrypted_content': 'c2lnbmVk',
      'summary': [
        {'type': 'summary_text', 'text': 'summary'},
      ],
    },
    {
      'type': 'function_call',
      'id': 'item',
      'call_id': 'call',
      'name': 'lookup',
      'arguments': '{"x":1}',
    },
    {
      'type': 'web_search_call',
      'id': 'search',
      'status': 'pending',
      'action': {'type': 'search', 'query': 'x'},
    },
  ],
};

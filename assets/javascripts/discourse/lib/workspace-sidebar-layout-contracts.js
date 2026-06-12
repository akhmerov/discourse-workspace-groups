export const contracts = [
  {
    "name": "dedupes snake case sections and casts booleans",
    "input": {
      "sections": [
        {
          "id": " papers ",
          "title": " Papers ",
          "channel_ids": ["41", "42", "42", "bad"],
          "collapsed": true
        },
        {
          "id": "students",
          "title": "Students",
          "channel_ids": [42, 43],
          "collapsed": "0"
        }
      ],
      "other_channel_ids": ["43", "44"],
      "other_collapsed": "off"
    },
    "normalized": {
      "sections": [
        {
          "id": "papers",
          "title": "Papers",
          "channel_ids": [41, 42],
          "collapsed": true
        },
        {
          "id": "students",
          "title": "Students",
          "channel_ids": [43],
          "collapsed": false
        }
      ],
      "other_channel_ids": [44],
      "other_collapsed": false
    }
  },
  {
    "name": "accepts camel case fields and skips invalid sections",
    "input": {
      "sections": [
        {
          "id": "",
          "title": " ",
          "channel_ids": null,
          "channelIds": {
            "0": "52",
            "1": "52",
            "2": "53"
          },
          "collapsed": "false"
        },
        "skip-me"
      ],
      "other_channel_ids": null,
      "otherChannelIds": "[53,54,\"0\",\"55x\"]",
      "other_collapsed": null,
      "otherCollapsed": "true"
    },
    "normalized": {
      "sections": [
        {
          "id": "section-1",
          "title": "Channels",
          "channel_ids": [52, 53],
          "collapsed": false
        }
      ],
      "other_channel_ids": [54, 55],
      "other_collapsed": true
    }
  }
];

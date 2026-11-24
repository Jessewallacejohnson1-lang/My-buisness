# Photo look: what a neighbour takes a photo for at a glance

A town's feed shows each photo on a card for an event. Your batch file has one photo per line: its `photo` key (`p3`)
and its `image`, a file to open with the Read tool. You don't know the event, and that is the point: open nothing but
your batch file and its images.

For each photo, say what a neighbour scrolling past would take the event for, from a one-second glance at the photo
alone: the people, what they are doing, and where. Small print, a poster on the wall, a book's page and a logo are not
seen in one second; leave them out. Under 15 words, plain. When a glance fits several kinds of event, name the two or
three likeliest. Nothing to go on (a portrait, a building, an object): say what it shows.

Done when every photo in the batch has its line. Answer with one JSON line per photo, nothing else:

    {"photo": "p3", "glance": "Students in costume singing on a stage: a school musical or play"}
    {"photo": "p4", "glance": "A woman's portrait"}

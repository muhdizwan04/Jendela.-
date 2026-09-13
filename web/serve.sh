#!/bin/zsh
# Preview the site locally. No build step: it is plain HTML and CSS on purpose,
# so it can be hosted anywhere and will still work in ten years.
cd "${0:A:h}"
print "http://localhost:8080"
python3 -m http.server 8080

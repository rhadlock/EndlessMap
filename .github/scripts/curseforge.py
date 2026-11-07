"""Endless Map: send a GitHub Release's zips to CurseForge (project 1725335).

Runs in GitHub Actions (.github/workflows/curseforge.yml) when a release is published - or by hand, with a tag and
"upload" unticked: the smoke test. Then everything is checked and prepared exactly as for a real upload, and nothing
is sent.

Each zip named EndlessMap-<Game>-<version>.zip (Game: Forever or Retail) becomes its own CurseForge file:
  display name  the zip's name (the author's format: EndlessMap-Forever-1.6.1.zip)
  game version  from the zip's TOC (## Interface: 16001 -> 1.60.1, 120105 -> 12.1.5), looked up in CurseForge's list
                under that game's version type; a version CurseForge does not list stops it all before anything is sent
  changelog     the release notes' section "## WoW Forever" / "## Retail" (with one game in the release and no such
                headings: the whole notes), up to a line "---"
  release type  release (beta for a GitHub pre-release)
The token is the repository secret CURSEFORGE_API_TOKEN. It is never printed; GitHub masks it in the log as well."""
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid
import zipfile

PROJECT = 1725335
CF = 'https://wow.curseforge.com/api'
REPO = os.environ.get('GITHUB_REPOSITORY', 'rhadlock/EndlessMap')
HEADINGS = {'Forever': 'WoW Forever', 'Retail': 'Retail'}  # the zip's game -> its section in the release notes
ZIP = re.compile(r'^EndlessMap-(Forever|Retail)-(.+)\.zip$')


def get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as r:
        return r.read()


def cf_get(path, token):
    try:
        return json.loads(get(CF + path, {'X-Api-Token': token}))
    except urllib.error.HTTPError as e:
        sys.exit('CurseForge answered %s %s for %s - is the token right?' % (e.code, e.reason, path))


def version_name(interface):
    """A TOC interface number as CurseForge names the game version: 120105 -> 12.1.5, 16001 -> 1.60.1."""
    i = int(interface)
    return '%d.%d.%d' % (i // 10000, i // 100 % 100, i % 100)


def toc_interfaces(data):
    """Every interface number the zip's top-level TOC files name."""
    found = set()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for n in z.namelist():
            if n.count('/') == 1 and n.endswith('.toc'):
                for line in z.read(n).decode('utf-8-sig', 'replace').splitlines():
                    m = re.match(r'##\s*Interface:\s*(.+)', line)
                    if m:
                        found |= {x.strip() for x in m.group(1).split(',') if x.strip()}
    return sorted(found)


def changelog(notes, game, games_in_release):
    text = re.split(r'^---\s*$', notes.replace('\r\n', '\n'), maxsplit=1, flags=re.M)[0]
    head = re.search(r'^## +%s *$' % re.escape(HEADINGS[game]), text, re.M)
    if head:
        rest = text[head.end():]
        nxt = re.search(r'^## ', rest, re.M)
        return (rest[:nxt.start()] if nxt else rest).strip()
    if games_in_release == 1 and not re.search(r'^## ', text, re.M):
        return text.strip()
    sys.exit('the release notes have no "## %s" section' % HEADINGS[game])


def upload(token, meta, name, data):
    b = uuid.uuid4().hex
    body = (('--%s\r\nContent-Disposition: form-data; name="metadata"\r\n\r\n%s\r\n' % (b, json.dumps(meta))).encode()
            + ('--%s\r\nContent-Disposition: form-data; name="file"; filename="%s"\r\nContent-Type: application/zip\r\n\r\n'
               % (b, name)).encode() + data + ('\r\n--%s--\r\n' % b).encode())
    req = urllib.request.Request('%s/projects/%d/upload-file' % (CF, PROJECT), data=body, method='POST',
                                 headers={'X-Api-Token': token, 'Content-Type': 'multipart/form-data; boundary=' + b})
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit('CurseForge refused %s: %s %s %s' % (name, e.code, e.reason, e.read()[:500]))


def main():
    token = os.environ.get('CURSEFORGE_API_TOKEN', '')
    tag = os.environ.get('TAG', '')
    send = os.environ.get('UPLOAD', '') == 'true'
    pre = os.environ.get('PRERELEASE', '') == 'true'
    if not token:
        sys.exit('the repository secret CURSEFORGE_API_TOKEN is missing')
    if not tag:
        sys.exit('no release tag given')
    print('Release %s - %s' % (tag, 'UPLOAD to CurseForge' if send else 'smoke test: nothing will be sent'))

    # 1. the token, and CurseForge's game versions
    types = cf_get('/game/version-types', token)
    versions = cf_get('/game/versions', token)
    print('The token works: CurseForge lists %d version types and %d game versions.' % (len(types), len(versions)))
    for t in sorted(types, key=lambda t: t['id']):
        names = [v['name'] for v in versions if v['gameVersionTypeID'] == t['id']]
        print('  type %-7s %-36s %3d versions, newest: %s' % (t['id'], t['name'], len(names), ', '.join(names[-4:])))
    kinds = {}
    for game in HEADINGS:
        hits = [t for t in types if game.lower() in t['name'].lower()]
        if len(hits) != 1:
            sys.exit('not exactly one CurseForge version type named like "%s": %s' % (game, [t['name'] for t in hits]))
        kinds[game] = hits[0]
        print('%s zips -> CurseForge type %s "%s"' % (game, hits[0]['id'], hits[0]['name']))

    # 2. the release and its zips - everything checked before anything is sent
    gh = {'Accept': 'application/vnd.github+json'}
    if os.environ.get('GITHUB_TOKEN'):
        gh['Authorization'] = 'Bearer ' + os.environ['GITHUB_TOKEN']
    rel = json.loads(get('https://api.github.com/repos/%s/releases/tags/%s' % (REPO, tag), gh))
    zips = [(a, ZIP.match(a['name'])) for a in rel['assets'] if ZIP.match(a['name'])]
    if not zips:
        sys.exit('the release has no EndlessMap-<Forever|Retail>-<version>.zip')
    plan = []
    for a, m in zips:
        game = m.group(1)
        data = get(a['browser_download_url'], {})
        if len(data) != a['size']:
            sys.exit('%s: downloaded %d bytes, GitHub lists %d' % (a['name'], len(data), a['size']))
        interfaces = toc_interfaces(data)
        wanted = {version_name(i): i for i in interfaces}
        ids = [v for v in versions if v['gameVersionTypeID'] == kinds[game]['id'] and v['name'] in wanted]
        if not ids:
            sys.exit('%s: CurseForge lists none of %s under "%s"' % (a['name'], sorted(wanted), kinds[game]['name']))
        meta = {'changelog': changelog(rel.get('body') or '', game, len(zips)), 'changelogType': 'markdown',
                'displayName': a['name'], 'gameVersions': [v['id'] for v in ids],
                'releaseType': 'beta' if pre else 'release'}
        print('\n%s (%d bytes): TOC interfaces %s -> %s; release type %s' % (
            a['name'], len(data), ', '.join(interfaces), ', '.join('%s (id %s)' % (v['name'], v['id']) for v in ids),
            meta['releaseType']))
        others = sorted(set(wanted) - {v['name'] for v in ids})
        if others:
            print('  not tagged (no "%s" version of that name): %s' % (kinds[game]['name'], ', '.join(others)))
        print('  changelog (%d characters):\n    %s' % (len(meta['changelog']), meta['changelog'][:600].replace('\n', '\n    ')))
        plan.append((a['name'], data, meta))

    # 3. send - or, in the smoke test, say what would have been sent
    if not send:
        print('\nSmoke test passed: %d file(s) ready for CurseForge project %d. Nothing was sent.' % (len(plan), PROJECT))
        return
    for name, data, meta in plan:
        r = upload(token, meta, name, data)
        print('Uploaded %s to CurseForge: file id %s' % (name, r.get('id')))


if __name__ == '__main__':
    main()

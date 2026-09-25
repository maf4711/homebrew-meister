#!/usr/bin/env python3
"""Read-only complete EMLX decoding. Inputs and contents use stdin/stdout only."""
import email.policy
import email.parser
import html.parser
import json
import plistlib
import re
import sys
from pathlib import Path

LIMIT = 1_000_000

class VisibleHTML(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.code_tag = None
    def handle_data(self, data):
        # Keep message text, including hidden text. CSS/JavaScript are rendering
        # code, not displayed email contents; native confirmation remains required.
        if self.code_tag is None:
            self.parts.append(data)
    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.code_tag = tag
        if self.code_tag is not None:
            return
        self.parts.append('\n')
        # Preserve alt/title text as message content as well.
        self.parts.extend(v for k, v in attrs if k in ('alt', 'title') and v)
    def handle_endtag(self, tag):
        if tag == self.code_tag:
            self.code_tag = None
            return
        if self.code_tag is not None:
            return
        self.parts.append('\n')

def decode(path, root):
    path = Path(path)
    if not path.is_absolute() or '..' in path.parts:
        raise ValueError()
    if not re.fullmatch(r'[1-9][0-9]*\.emlx', path.name):
        raise ValueError()
    relative = path.relative_to(root)
    current = root
    for component in relative.parts:
        current /= component
        if current.is_symlink():
            raise ValueError()
    if not path.resolve().is_relative_to(root):
        raise ValueError()
    with path.open('rb') as handle:
        raw = handle.read(LIMIT + 65537)
    if len(raw) > LIMIT + 65536:
        raise ValueError()
    first, separator, remaining = raw.partition(b'\n')
    # Apple Mail reserves a padded width for the decimal MIME byte count.
    if not separator or len(first) > 32 or not re.fullmatch(rb'[0-9]{1,7}[ \t]*\r?', first):
        raise ValueError()
    length = int(first)
    if length <= 0 or length > LIMIT or len(remaining) < length:
        raise ValueError()
    suffix = remaining[length:].strip()
    if suffix:
        plistlib.loads(suffix)
    payload = remaining[:length]
    message = email.parser.BytesParser(policy=email.policy.default).parsebytes(payload)
    if len(message.get_all('Subject', [])) != 1 or len(message.get_all('Message-ID', [])) != 1:
        raise ValueError()
    subject = str(message['Subject'])
    rfc = str(message['Message-ID']).strip()
    if rfc.startswith('<') and rfc.endswith('>'):
        rfc = rfc[1:-1]
    if not rfc or len(rfc) > 998 or re.search(r'[\x00-\x20\x7f<>]', rfc):
        raise ValueError()
    pieces = []
    count = 0
    def visit(part, depth=0):
        nonlocal count
        count += 1
        if count > 100 or depth > 12 or part.defects:
            raise ValueError()
        if any(getattr(v, 'defects', ()) for v in part.values()):
            raise ValueError()
        kind = part.get_content_type()
        if part.get_content_disposition() == 'attachment' or part.get_filename():
            raise ValueError()
        if kind in ('multipart/encrypted', 'multipart/signed', 'message/rfc822'):
            raise ValueError()
        if part.is_multipart():
            if part.get_content_maintype() != 'multipart':
                raise ValueError()
            for child in part.iter_parts():
                visit(child, depth + 1)
            return
        if kind not in ('text/plain', 'text/html'):
            raise ValueError()
        encoding = str(part.get('Content-Transfer-Encoding', '7bit')).lower().strip()
        if encoding not in ('7bit', '8bit', 'binary', 'quoted-printable', 'base64'):
            raise ValueError()
        if encoding == 'quoted-printable' and re.search(r'=(?![0-9A-Fa-f]{2}|\r?\n)', part.get_payload()):
            raise ValueError()
        raw_text = part.get_payload(decode=True)
        if part.defects or not isinstance(raw_text, bytes):
            raise ValueError()
        text = raw_text.decode(part.get_content_charset() or 'ascii', errors='strict')
        if kind == 'text/html':
            parser = VisibleHTML()
            parser.feed(text)
            parser.close()
            text = '\n'.join(parser.parts)
        pieces.append(text)
    visit(message)
    body = '\n\n'.join(pieces)
    if not body.strip() or len(body.encode('utf-8')) > LIMIT:
        raise ValueError()
    return {'body': body, 'rfcMessageId': rfc, 'subject': subject}

def main():
    request = json.loads(sys.stdin.buffer.read(100_000))
    account = request['accountID']
    if not isinstance(account, str) or not re.fullmatch(r'[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}', account):
        raise ValueError()
    # Optional mailRoot is supplied only by the trusted Node adapter/test harness.
    base = Path(request['mailRoot'])
    root = base / account / 'INBOX.mbox'
    if not base.is_absolute() or '..' in base.parts or any(p.is_symlink() for p in [base, *base.parents]):
        raise ValueError()
    if root.is_symlink() or root.parent.is_symlink() or not root.is_dir():
        raise ValueError()
    root = root.resolve()
    rows = request['rows']
    if not isinstance(rows, list) or len(rows) > 25:
        raise ValueError()
    output = []
    for row in rows:
        value = None
        try:
            if not isinstance(row['id'], str) or not re.fullmatch(r'[1-9][0-9]*', row['id']):
                raise ValueError()
            if Path(row['path']).name != row['id'] + '.emlx':
                raise ValueError()
            value = decode(row['path'], root)
        except Exception:
            pass
        output.append({'id': row['id'], 'value': value})
    print(json.dumps({'rows': output}, ensure_ascii=False))

if __name__ == '__main__':
    try:
        main()
    except Exception:
        sys.stderr.write('Local mail content unavailable\n')
        sys.exit(1)

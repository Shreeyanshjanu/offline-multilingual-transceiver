"""Interactive local TCP test peer. Commands: send <label>, repeat, drop, status, quit.

For an Android host: adb forward tcp:17070 tcp:7070
  python tools/background_connection_peer.py --connect 127.0.0.1 --port 17070 --peers 2
For an Android client: adb reverse tcp:7070 tcp:17071
  python tools/background_connection_peer.py --listen --port 17071
Then configure the phone to join 127.0.0.1:7070. Test messages use visible test labels.
"""
import argparse
import json
import socket
import threading
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--connect')
parser.add_argument('--listen', action='store_true')
parser.add_argument('--port', type=int, default=17070)
parser.add_argument('--peers', type=int, default=1)
args = parser.parse_args()
peers = []
lock = threading.Lock()
stopped = threading.Event()
last = None
listener = None


def report(**values):
    print(json.dumps(values), flush=True)


def read(peer):
    try:
        with peer.makefile('rb') as stream:
            for line in stream:
                try:
                    data = json.loads(line)
                    report(receivedId=data.get('id'))
                except ValueError:
                    report(error='Invalid frame')
    except OSError:
        pass
    finally:
        with lock:
            if peer in peers:
                peers.remove(peer)
        peer.close()
        report(event='peer_disconnected')


def attach(peer):
    peer.settimeout(None)
    with lock:
        peers.append(peer)
    report(event='peer_connected')
    threading.Thread(target=read, args=(peer,), daemon=True).start()


def accept():
    while not stopped.is_set():
        try:
            peer, _ = listener.accept()
            attach(peer)
        except OSError:
            return


def drop():
    with lock:
        active = list(peers)
    for peer in active:
        try:
            peer.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        peer.close()


try:
    if args.listen:
        listener = socket.socket()
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(('127.0.0.1', args.port))
        listener.listen(8)
        threading.Thread(target=accept, daemon=True).start()
    else:
        for _ in range(args.peers):
            attach(socket.create_connection((args.connect or '127.0.0.1', args.port), timeout=5))
    report(event='ready', port=args.port)
    while True:
        try:
            command = input().strip()
        except EOFError:
            break
        if command == 'quit':
            break
        if command == 'drop':
            drop()
        elif command == 'status':
            with lock:
                report(peers=len(peers))
        elif command == 'repeat' or command.startswith('send '):
            if command != 'repeat':
                last = {'id': f'bg-verification-{time.time_ns()}', 'type': 'speech', 'language': 'en',
                        'message': 'iTantra background test. ' + command[5:], 'timestamp': int(time.time() * 1000),
                        'sender': {'callsign': 'Verification peer', 'role': 'Test'}}
            if last is None:
                continue
            with lock:
                target = peers[0] if peers else None
            if target is None:
                report(error='No connected peer')
                continue
            try:
                target.sendall((json.dumps(last, ensure_ascii=False) + '\n').encode('utf-8'))
                report(sentId=last['id'], repeated=command == 'repeat')
            except OSError:
                report(error='Send failed')
finally:
    stopped.set()
    if listener:
        listener.close()
    drop()

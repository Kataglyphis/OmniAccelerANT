# Forwards TCP from 127.0.0.1:<listen> to :<target>; once <flag> exists, connections older than it carry nothing but stay open.
import asyncio
import os
import sys
import time

LISTEN, TARGET, FLAG = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]


def silenced(born):
    try:
        return born < os.path.getmtime(FLAG)
    except OSError:
        return False


async def pipe(reader, writer, born):
    try:
        while data := await reader.read(65536):
            if silenced(born):
                # What a sleeping laptop leaves behind: nothing arrives and nothing closes.
                await asyncio.sleep(10**9)
            writer.write(data)
            await writer.drain()
    except OSError:
        pass
    finally:
        if not silenced(born):
            writer.close()


async def handle(client_reader, client_writer):
    born = time.time()
    try:
        server_reader, server_writer = await asyncio.open_connection("127.0.0.1", TARGET)
    except OSError:
        client_writer.close()
        return
    await asyncio.gather(pipe(client_reader, server_writer, born), pipe(server_reader, client_writer, born))


async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", LISTEN)
    async with server:
        await server.serve_forever()


asyncio.run(main())

"""Run the real PAM authentication/session API with only fixture credentials."""

import argparse
import ctypes
import ctypes.util
import json


class Message(ctypes.Structure):
    _fields_ = [("style", ctypes.c_int), ("text", ctypes.c_char_p)]


class Response(ctypes.Structure):
    _fields_ = [("text", ctypes.c_void_p), ("returncode", ctypes.c_int)]


Callback = ctypes.CFUNCTYPE(
    ctypes.c_int,
    ctypes.c_int,
    ctypes.POINTER(ctypes.POINTER(Message)),
    ctypes.POINTER(ctypes.POINTER(Response)),
    ctypes.c_void_p,
)


class Conversation(ctypes.Structure):
    _fields_ = [("callback", Callback), ("data", ctypes.c_void_p)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("service")
    parser.add_argument("user")
    parser.add_argument("password")
    parser.add_argument("--library", required=True)
    args = parser.parse_args()
    libc = ctypes.CDLL(ctypes.util.find_library("c"))
    libc.calloc.argtypes = [ctypes.c_size_t, ctypes.c_size_t]
    libc.calloc.restype = ctypes.c_void_p
    libc.strdup.argtypes = [ctypes.c_char_p]
    libc.strdup.restype = ctypes.c_void_p

    @Callback
    def answer(count, messages, output, _data):
        memory = libc.calloc(count, ctypes.sizeof(Response))
        if not memory:
            return 19
        responses = ctypes.cast(memory, ctypes.POINTER(Response))
        for index in range(count):
            style = messages[index].contents.style
            if style in (1, 2):
                value = args.password if style == 1 else args.user
                responses[index].text = libc.strdup(value.encode())
            elif style not in (3, 4):
                return 19
        output[0] = responses
        return 0

    pam = ctypes.CDLL(args.library)
    handle = ctypes.c_void_p()
    conversation = Conversation(answer, None)
    pam.pam_start.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.POINTER(Conversation),
        ctypes.POINTER(ctypes.c_void_p),
    ]
    pam.pam_authenticate.argtypes = [ctypes.c_void_p, ctypes.c_int]
    pam.pam_acct_mgmt.argtypes = [ctypes.c_void_p, ctypes.c_int]
    pam.pam_open_session.argtypes = [ctypes.c_void_p, ctypes.c_int]
    pam.pam_setcred.argtypes = [ctypes.c_void_p, ctypes.c_int]
    pam.pam_close_session.argtypes = [ctypes.c_void_p, ctypes.c_int]
    pam.pam_end.argtypes = [ctypes.c_void_p, ctypes.c_int]
    status = pam.pam_start(
        args.service.encode(),
        args.user.encode(),
        ctypes.byref(conversation),
        ctypes.byref(handle),
    )
    assert status == 0, status
    result = {"auth": pam.pam_authenticate(handle, 0)}
    try:
        if result["auth"] == 0:
            result["account"] = pam.pam_acct_mgmt(handle, 0)
            if result["account"] == 0:
                result["credentials"] = pam.pam_setcred(handle, 2)
                if result["credentials"] == 0:
                    result["session"] = pam.pam_open_session(handle, 0)
                    if result["session"] == 0:
                        pam.pam_close_session(handle, 0)
                    result["delete_credentials"] = pam.pam_setcred(handle, 4)
    finally:
        pam.pam_end(handle, result["auth"])
    print(json.dumps(result))


if __name__ == "__main__":
    main()

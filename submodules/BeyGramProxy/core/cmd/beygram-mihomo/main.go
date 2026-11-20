// Command beygram-mihomo is built as a C archive for the iOS app. It exports
// BGMihomoInvoke, which takes one JSON request and returns one JSON reply, and
// BGMihomoFree, which frees a reply. The archive is built with
// go build -buildmode=c-archive. Nothing here is run by the app's tests.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"unsafe"

	"beygram/mihomoproxy/bridge"
)

var core = bridge.New()

// BGMihomoInvoke handles one JSON request. The caller frees the result with BGMihomoFree.
//
//export BGMihomoInvoke
func BGMihomoInvoke(request *C.char) *C.char {
	reply := core.Invoke([]byte(C.GoString(request)))
	return C.CString(string(reply))
}

// BGMihomoFree frees a reply returned by BGMihomoInvoke.
//
//export BGMihomoFree
func BGMihomoFree(reply *C.char) {
	C.free(unsafe.Pointer(reply))
}

func main() {}

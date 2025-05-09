// -*- C++ -*-
//===----------------------------------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef _LIBCPP___CONFIGURATION_LANGUAGE_H
#define _LIBCPP___CONFIGURATION_LANGUAGE_H

/* zig patch: instead of including __config_site, zig adds -D flags when compiling */

#ifndef _LIBCPP_HAS_NO_PRAGMA_SYSTEM_HEADER
#  pragma GCC system_header
#endif

// NOLINTBEGIN(libcpp-cpp-version-check)
#ifdef __cplusplus
#  if __cplusplus <= 201103L
#    define _LIBCPP_STD_VER 11
#  elif __cplusplus <= 201402L
#    define _LIBCPP_STD_VER 14
#  elif __cplusplus <= 201703L
#    define _LIBCPP_STD_VER 17
#  elif __cplusplus <= 202002L
#    define _LIBCPP_STD_VER 20
#  elif __cplusplus <= 202302L
#    define _LIBCPP_STD_VER 23
#  else
// Expected release year of the next C++ standard
#    define _LIBCPP_STD_VER 26
#  endif
#endif // __cplusplus
// NOLINTEND(libcpp-cpp-version-check)

#if defined(__cpp_rtti) && __cpp_rtti >= 199711L
#  define _LIBCPP_HAS_RTTI 1
#else
#  define _LIBCPP_HAS_RTTI 0
#endif

#if defined(__cpp_exceptions) && __cpp_exceptions >= 199711L
#  define _LIBCPP_HAS_EXCEPTIONS 1
#else
#  define _LIBCPP_HAS_EXCEPTIONS 0
#endif

#endif // _LIBCPP___CONFIGURATION_LANGUAGE_H

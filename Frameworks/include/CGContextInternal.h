//******************************************************************************
//
// Copyright (c) 2015 Microsoft Corporation. All rights reserved.
//
// This code is licensed under the MIT License (MIT).
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
//******************************************************************************

#pragma once

#include <COMIncludes.h>
#import <DWrite.h>
#include <COMIncludes_End.h>

#import "CGImageInternal.h"
#import "CoreGraphics/CGContext.h"
#import "CoreGraphicsInternal.h"
#import "Starboard.h"

#import <objc/runtime.h>

class CGContextImpl;
COREGRAPHICS_EXPORT void EbrCenterTextInRectVertically(CGRect* rect, CGSize* textSize, id font);
COREGRAPHICS_EXPORT CGContextRef _CGBitmapContextCreateWithTexture(int width, int height, const std::shared_ptr<IDisplayTexture>& texture);
COREGRAPHICS_EXPORT CGContextRef _CGBitmapContextCreateWithFormat(int width, int height, __CGSurfaceFormat fmt);
COREGRAPHICS_EXPORT CGImageRef CGBitmapContextGetImage(CGContextRef ctx);
COREGRAPHICS_EXPORT void CGContextDrawImageRect(CGContextRef ctx, CGImageRef img, CGRect src, CGRect dst);
COREGRAPHICS_EXPORT void CGContextClearToColor(CGContextRef ctx, float r, float g, float b, float a);
COREGRAPHICS_EXPORT bool CGContextIsDirty(CGContextRef ctx);
COREGRAPHICS_EXPORT void CGContextSetDirty(CGContextRef ctx, bool dirty);
COREGRAPHICS_EXPORT void CGContextReleaseLock(CGContextRef ctx);
COREGRAPHICS_EXPORT CGContextImpl* CGContextGetBacking(CGContextRef ctx);
COREGRAPHICS_EXPORT CGBlendMode CGContextGetBlendMode(CGContextRef ctx);

COREGRAPHICS_EXPORT CGImageRef CGPNGImageCreateFromFile(NSString* path);
COREGRAPHICS_EXPORT CGImageRef CGPNGImageCreateFromData(NSData* data);

COREGRAPHICS_EXPORT CGImageRef CGJPEGImageCreateFromFile(NSString* path);
COREGRAPHICS_EXPORT CGImageRef CGJPEGImageCreateFromData(NSData* data);
COREGRAPHICS_EXPORT bool CGContextIsPointInPath(CGContextRef c, bool eoFill, float x, float y);

COREGRAPHICS_EXPORT void CGContextDrawGlyphRun(CGContextRef ctx, const DWRITE_GLYPH_RUN* glyphRun);

// TODO 1077:: Remove once D2D render target is implemented
COREGRAPHICS_EXPORT void _CGContextSetScaleFactor(CGContextRef ctx, float scale);

class __CGContext : private objc_object {
public:
    float scale;
    CGContextImpl* _backing;

    __CGContext(CGImageRef pDest);
    ~__CGContext();

    CGContextImpl* Backing();
};

#include "CGContextImpl.h"
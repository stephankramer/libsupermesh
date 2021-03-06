/******************************************************************************
 * Project:  libsidx - A C API wrapper around libspatialindex
 * Purpose:  C++ objects to implement the count visitor.
 * Author:   Leonard Norrgård, leonard.norrgard@refactor.fi
 ******************************************************************************
 * Copyright (c) 2010, Leonard Norrgård
 *
 * All rights reserved.
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
******************************************************************************/

/*
This is a modified version of libspatialindex for use with libsupermesh.
Code first added 2016-03-01.
*/

#include <spatialindex/capi/sidx_impl.h>

CountVisitor::CountVisitor(): nResults(0)
{
}

CountVisitor::~CountVisitor()
{

}

void CountVisitor::visitNode(const libsupermesh::SpatialIndex::INode& )
{

}

void CountVisitor::visitData(const libsupermesh::SpatialIndex::IData& )
{
   nResults += 1;
}

void CountVisitor::visitData(std::vector<const libsupermesh::SpatialIndex::IData*>& )
{
}

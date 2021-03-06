/******************************************************************************
 * Project:  libsidx - A C API wrapper around libspatialindex
 * Purpose:	 C++ objects to implement the bounds query.
 * Author:   Howard Butler, hobu.inc@gmail.com
 ******************************************************************************
 * Copyright (c) 2009, Howard Butler
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

BoundsQuery::BoundsQuery() 
{
	m_bounds = new libsupermesh::SpatialIndex::Region;
}

void BoundsQuery::getNextEntry( const libsupermesh::SpatialIndex::IEntry& entry, 
								libsupermesh::SpatialIndex::id_type&, 
								bool& hasNext) 
{
	libsupermesh::SpatialIndex::IShape* ps;
	entry.getShape(&ps);
	ps->getMBR(*m_bounds);
	delete ps;
		
	hasNext = false;
}

/*
 * Copyright 2014 The Sculptor Project Team, including the original 
 * author or authors.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.sculptor.generator.template.rest

import org.junit.BeforeClass
import org.junit.Test
import org.sculptor.generator.test.GeneratorTestBase

import static org.sculptor.generator.test.GeneratorTestExtensions.*

class ResourceTmplTest extends GeneratorTestBase {

	static val TEST_NAME = "rest"

	new() {
		super(TEST_NAME)
	}

	@BeforeClass
	def static void setup() {
		runGenerator(TEST_NAME)
	}

	@Test
	def void assertFullQualifiedPlanetInGaeKeyIdPropertyEditor() {
		val code = getFileText(TO_GEN_SRC + "/org/helloworld/milkyway/rest/PlanetResourceBase.java");
		assertContainsConsecutiveFragments(code,
			#['com.google.appengine.api.datastore.Key key = com.google.appengine.api.datastore.KeyFactory.createKey(',
				'org.helloworld.milkyway.domain.Planet.class.getSimpleName(), Long.valueOf(text));'])
	}

}

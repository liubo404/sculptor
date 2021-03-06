/*
 * Copyright 2007 The Fornax Project Team, including the original
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

package org.sculptor.generator.template.db

import java.util.Set
import javax.inject.Inject
import org.sculptor.generator.ext.DbHelper
import org.sculptor.generator.ext.Helper
import org.sculptor.generator.ext.Properties
import org.sculptor.generator.util.DbHelperBase
import org.sculptor.generator.util.OutputSlot
import org.sculptor.generator.util.PropertiesBase
import sculptormetamodel.Application
import sculptormetamodel.Attribute
import sculptormetamodel.BasicType
import sculptormetamodel.DomainObject
import sculptormetamodel.Enum
import sculptormetamodel.Reference
import org.sculptor.generator.chain.ChainOverridable

@ChainOverridable
class OracleDDLTmpl {

	@Inject extension DbHelperBase dbHelperBase
	@Inject extension DbHelper dbHelper
	@Inject extension Helper helper
	@Inject extension PropertiesBase propertiesBase
	@Inject extension Properties properties

def String ddl(Application it) {
	val manyToManyRelations = it.resolveManyToManyRelations(true)
	fileOutput("dbschema/" + name + "_ddl.sql", OutputSlot::TO_GEN_RESOURCES, '''
	�IF isDdlDropToBeGenerated()�
		-- ###########################################
		-- # Drop
		-- ###########################################
		-- Drop index
		�it.getDomainObjectsInCreateOrder(false).map[dropIndex(it)].join()�

		-- Drop many to many relations
		�it.resolveManyToManyRelations(false).map[dropTable(it)].join()�

		-- Drop normal entities
		�it.getDomainObjectsInCreateOrder(false).filter(d | !isInheritanceTypeSingleTable(getRootExtends(d.^extends))).map[dropTable(it)].join()�

		-- Drop pk sequence
		�dropSequence(it)�
	�ENDIF�

	-- ###########################################
	-- # Create
	-- ###########################################
	-- Create pk sequence
	�createSequence(it)�

	-- Create normal entities
	�it.getDomainObjectsInCreateOrder(true).filter(d | !isInheritanceTypeSingleTable(getRootExtends(d.^extends))).map[createTable(it)].join()�

	-- Create many to many relations
	�manyToManyRelations.map[createTable(it)].join�

	-- Primary keys
	�it.getDomainObjectsInCreateOrder(true).filter(d | d.attributes.exists(a|a.name == "id")).map[idPrimaryKey(it)].join()�
	�manyToManyRelations.map[manyToManyPrimaryKey(it)].join�

	-- Unique constraints
	�it.getDomainObjectsInCreateOrder(true).filter(d | !isInheritanceTypeSingleTable(getRootExtends(d.^extends))) .map[uniqueConstraint(it)].join()�

	-- Foreign key constraints
	�it.getDomainObjectsInCreateOrder(true).filter(d | d.^extends != null && !isInheritanceTypeSingleTable(getRootExtends(d.^extends))).map[extendsForeignKeyConstraint(it)].join()�

	�it.getDomainObjectsInCreateOrder(true).filter(d | !isInheritanceTypeSingleTable(getRootExtends(d.^extends))).map[foreignKeyConstraint(it)].join()�
	�manyToManyRelations.map[foreignKeyConstraint(it)].join()�

	-- Index
	�it.getDomainObjectsInCreateOrder(true).map[index(it)].join()�
	'''
	)
}

def String dropSequence(Application it) {
	'''
	DROP SEQUENCE hibernate_sequence;
	'''
}

def String createSequence(Application it) {
	'''
	CREATE SEQUENCE hibernate_sequence;
	'''
}

def String dropTable(DomainObject it) {
	'''
	DROP TABLE �getDatabaseName(it)� CASCADE�IF dbProduct == "oracle"� CONSTRAINTS PURGE�ENDIF�;
	'''
}


def String createTable(DomainObject it) {
	'''
	�val alreadyUsedColumns = <String>newHashSet()�
	CREATE TABLE �getDatabaseName(it)� (
	�columns(it, false, alreadyUsedColumns)��
	IF isInheritanceTypeSingleTable(it)��inheritanceSingleTable(it, alreadyUsedColumns)��ENDIF��
	IF ^extends != null��extendsForeignKeyColumn(it, !alreadyUsedColumns.isEmpty)��ENDIF�
	)�afterCreateTable(it)�;
	
	'''
}

def String afterCreateTable(DomainObject it) {
	'''�IF hasHint(it, "tablespace")�
		TABLESPACE �getHint(it, "tablespace").toUpperCase()��ENDIF�'''
}

def String columns(DomainObject it, boolean initialComma, Set<String> alreadyDone) {
	val strColumns = new StringBuilder()
	strColumns.append(it.attributes
		.filter[e | !(e.transient || alreadyDone.contains(e.getDatabaseName()) || e.systemAttributeToPutLast)]
		.map[e | alreadyDone.add(e.getDatabaseName()); ",\n\t" + column(e, "")]
		.join
	)

	strColumns.append(it.getBasicTypeReferences()
		.filter[e | !(e.transient || alreadyDone.contains(e.getDatabaseName()))]
		.map[e | alreadyDone.add(e.getDatabaseName()); ",\n\t" + containedColumns(e, "", false)]
		.join
	)

	strColumns.append(it.getEnumReferences()
		.filter[e | !(e.transient || alreadyDone.contains(e.getDatabaseName()))]
		.map[e | alreadyDone.add(e.getDatabaseName()); ",\n\t" + enumColumn(e, "", false)]
		.join
	)

	strColumns.append(if (it.module == null) "" else it.module.application.modules
		.map[domainObjects].flatten.map[references].flatten
		.filter[e | !e.transient && e.to == it && e.many && e.opposite == null && e.isInverse()]
		.filter[e | !(alreadyDone.contains(e.getDatabaseName()))]
		.map[e | alreadyDone.add(e.getDatabaseName()); ",\n\t" + uniManyForeignKeyColumn(e)]
		.join
	)

	strColumns.append(it.references
		.filter(r | !r.transient && !r.many && r.to.hasOwnDatabaseRepresentation())
		.filter[e | !((e.isOneToOne() && e.isInverse()) || alreadyDone.contains(e.getDatabaseName()))]
		.map[e | alreadyDone.add(e.getDatabaseName()); ",\n\t" + foreignKeyColumn(e)]
		.join
	)

	strColumns.append(it.attributes
		.filter[e | !(e.transient || alreadyDone.contains(e.getDatabaseName()) || ! e.isSystemAttributeToPutLast() )]
		.map[e | alreadyDone.add(e.getDatabaseName()); ",\n\t" + column(e, "")]
		.join
	)
	if (initialComma || strColumns.length < 2)
		strColumns.toString
	else
		strColumns.substring(2)
}

def String column(Attribute it, String prefix) {
	'''�column(it, prefix, false) �'''
}

def String column(Attribute it, String prefix, boolean parentIsNullable) {
	'''�getDatabaseName(prefix, it)� �getDatabaseType(it)��if (parentIsNullable) "" else getDatabaseTypeNullability(it)�'''
}

def String enumColumn(Reference it, String prefix, boolean parentIsNullable) {
	'''�getDatabaseName(prefix, it)� �getEnumDatabaseType(it)��if (parentIsNullable) "" else getDatabaseTypeNullability(it)�'''
}

def String containedColumns(Reference it, String prefix, boolean parentIsNullable) {
	val rows = new StringBuilder()
	rows.append(it.to.attributes.filter[a | !a.transient].map[a | ",\n\t" + column(a, getDatabaseName(prefix, it), parentIsNullable || nullable)].join)
	rows.append(it.to.references.filter[r | !r.transient && r.to instanceof Enum].map[r | ",\n\t" + enumColumn(r, getDatabaseName(prefix, it), parentIsNullable || nullable)].join)
	rows.append(it.to.references.filter[r | !r.transient && r.to instanceof BasicType].map[b | containedColumns(b, getDatabaseName(it), parentIsNullable || nullable)].join)
	if (rows.length < 3)
		""
	else
		rows.substring(3)
}

def String inheritanceSingleTable(DomainObject it, Set<String> alreadyUsedColumns) {
	'''
	,
	�discriminatorColumn(it) �
	�it.getAllSubclasses().map[s | columns(s, true, alreadyUsedColumns)].join�'''
}

def String discriminatorColumn(DomainObject it) {
	'''�inheritance.discriminatorColumnName()� �inheritance.getDiscriminatorColumnDatabaseType()� NOT NULL'''
}

def String idPrimaryKey(DomainObject it) {
	'''
	ALTER TABLE �getDatabaseName(it)� ADD CONSTRAINT PK_�getDatabaseName(it)�
		PRIMARY KEY (�attributes.filter[a | a.name == "id"].head.getDatabaseName()�)�
		afterIdPrimaryKey(it)�;
	'''
}

def String afterIdPrimaryKey(DomainObject it) {
	'''
		�usingIndexTablespace(it)�'''
}

def String manyToManyPrimaryKey(DomainObject it) {
	'''
	ALTER TABLE �getDatabaseName(it)� ADD CONSTRAINT PK_�getDatabaseName(it)�
		PRIMARY KEY (�FOR r : references SEPARATOR ", "��r.getForeignKeyName()��ENDFOR�)�
		afterManyToManyPrimaryKey(it)�;
	'''
}

def String afterManyToManyPrimaryKey(DomainObject it) {
	'''
	�usingIndexTablespace(it)�'''
}

def String usingIndexTablespace(DomainObject it) {
	'''
	�IF hasHint(it, "tablespace")�	USING INDEX TABLESPACE �getHint(it, "tablespace").toUpperCase()��ENDIF�
	'''
}

def String foreignKeyColumn(Reference it) {
	'''
	�IF it.hasOpposite() && "list" == opposite.getCollectionType()��
		opposite.getListIndexColumnName()� �getListIndexDatabaseType()��",\n\t"�
	�ENDIF�
	�getForeignKeyName(it)� �getForeignKeyType(it)�'''
}

def String uniManyForeignKeyColumn(Reference it) {
	'''
	�IF "list" == getCollectionType()��
		getListIndexColumnName(it)� �getListIndexDatabaseType()��",\n\t"�
	�ENDIF�
	�getOppositeForeignKeyName(it)� �from.getForeignKeyType()�'''
}

def String extendsForeignKeyColumn(DomainObject it, boolean initialComma) {
	'''
	�IF initialComma�,
	�ENDIF�
		�^extends.getExtendsForeignKeyName()� �^extends.getForeignKeyType() � NOT NULL'''
}

def dispatch String foreignKeyConstraint(DomainObject it) {
	'''
		�it.references.filter(r | !r.transient && !r.many && r.to.hasOwnDatabaseRepresentation()).filter[e | !(e.isOneToOne() && e.isInverse())].map[foreignKeyConstraint(it)].join()�
		�it.references.filter(r | !r.transient && r.many && r.opposite == null && r.isInverse() && (r.to.hasOwnDatabaseRepresentation())).map[uniManyForeignKeyConstraint(it)].join()�
	'''
}

def dispatch String foreignKeyConstraint(Reference it) {
	'''
	
	-- Reference from �from.name�.�name� to �to.name�
	ALTER TABLE �from.getDatabaseName()� ADD CONSTRAINT FK_�truncateLongDatabaseName(from.getDatabaseName(), getDatabaseName(it))�
		FOREIGN KEY (�getForeignKeyName(it)�) REFERENCES �to.getRootExtends().getDatabaseName()� (�to.getRootExtends().getIdAttribute().getDatabaseName()�)� IF (opposite != null) && opposite.isDbOnDeleteCascade()� ON DELETE CASCADE�ENDIF�;
	�foreignKeyIndex(it)�
	'''
}

def String foreignKeyIndex(Reference it) {
	'''
	CREATE INDEX IX_�truncateLongDatabaseName(from.getDatabaseName(), getForeignKeyName(it))� ON �from.getDatabaseName()� (�getForeignKeyName(it)�);
	'''
}

def String uniManyForeignKeyConstraint(Reference it) {
	'''
	
	-- Reference from �from.name�.�name� to �to.name�
	ALTER TABLE �to.getDatabaseName()� ADD CONSTRAINT FK_�truncateLongDatabaseName(to.getDatabaseName(), from.getDatabaseName())�
		FOREIGN KEY (�getOppositeForeignKeyName(it)�) REFERENCES �from.getRootExtends().getDatabaseName()� (�from.getRootExtends().getIdAttribute().getDatabaseName()�);
	�uniManyForeignKeyIndex(it)�
	'''
}

def String uniManyForeignKeyIndex(Reference it) {
	'''
	CREATE INDEX IX_�truncateLongDatabaseName(to.getDatabaseName(), getOppositeForeignKeyName(it))� ON �to.getDatabaseName()� (�getOppositeForeignKeyName(it)�);
	'''
}

def String extendsForeignKeyConstraint (DomainObject it) {
	'''
	
	-- Entity �name� extends �^extends.name�
	ALTER TABLE �getDatabaseName(it)� ADD CONSTRAINT FK_�truncateLongDatabaseName(getDatabaseName(it), ^extends.getDatabaseName())�
		FOREIGN KEY (�^extends.getExtendsForeignKeyName()�) REFERENCES �^extends.getRootExtends().getDatabaseName()� (�^extends.getRootExtends().getIdAttribute().getDatabaseName()�);
	�extendsForeignKeyIndex(it)�
	'''
}

def String extendsForeignKeyIndex(DomainObject it) {
	'''
	CREATE INDEX IX_�truncateLongDatabaseName(getDatabaseName(it), ^extends.getExtendsForeignKeyName())� ON �getDatabaseName(it)� (�^extends.getExtendsForeignKeyName()�);
	'''
}

def String uniqueConstraint(DomainObject it) {
	'''
	�IF hasUniqueConstraints(it)�
	ALTER TABLE �getDatabaseName(it)�
		�IF attributes.exists(a | a.isUuid()) �
			ADD CONSTRAINT UQ_�getDatabaseName(it)� UNIQUE (UUID)�
		ELSE�
			ADD CONSTRAINT UQ_�getDatabaseName(it)� UNIQUE (�
			FOR key : getAllNaturalKeys(it) SEPARATOR ", "��
				IF key.isBasicTypeReference()��
					FOR a : (key as Reference).to.getAllNaturalKeys() SEPARATOR ", "
						��getDatabaseName(getDatabaseName(key), a)��
					ENDFOR��
				ELSE
					��key.getDatabaseName()��
				ENDIF��
			ENDFOR�)�
		ENDIF��
		afterUniqueConstraint(it)�;
	�ENDIF�
	'''
}

def String afterUniqueConstraint(DomainObject it) {
	'''�usingIndexTablespace(it)�'''
}

def String index(DomainObject it) {
	'''
	�it.attributes.filter[a | a.index == true].map[i | index(i, "", it)].join()�
	�it.getBasicTypeReferences().map[containedColumnIndex(it)].join()�
	�IF isInheritanceTypeSingleTable(it)�
		�discriminatorIndex(it)�
	�ENDIF�
	'''
}

def String containedColumnIndex(Reference it) {
	'''�it.to.attributes.filter(a | a.index == true).map[a | index(a, getDatabaseName(it) + "_", from)].join�'''
}

def String index(Attribute it, String prefix, DomainObject domainObject) {
	var actualDomainObject = if (domainObject.^extends != null && isInheritanceTypeSingleTable(domainObject.getRootExtends())) domainObject.getRootExtends() else domainObject
	'''
	CREATE INDEX IX_�truncateLongDatabaseName(actualDomainObject.getDatabaseName(), getDatabaseName(prefix, it))�
		ON �actualDomainObject.getDatabaseName()� (�getDatabaseName(prefix, it)� ASC)
		�afterIndex(it, prefix, domainObject)�;
	'''
}

def String afterIndex(Attribute it, String prefix, DomainObject domainObject) {
	'''
	�IF domainObject.hasHint("tablespace")�
		TABLESPACE �domainObject.getHint("tablespace").toUpperCase()�
	�ENDIF�
	'''
}

def String discriminatorIndex(DomainObject it) {
	'''
	CREATE INDEX IX_�truncateLongDatabaseName(getDatabaseName(it), inheritance.discriminatorColumnName())�
		ON �getDatabaseName(it)� (�inheritance.discriminatorColumnName()� ASC);
	'''
}

def String dropIndex(DomainObject it) {
	'''
	�it.attributes.filter(a | a.index == true).map[a | dropIndex(a, "", it)].join()�
	�it.getBasicTypeReferences().map[dropContainedColumnIndex(it)].join()�
	�IF isInheritanceTypeSingleTable(it)�
		�dropDiscriminatorIndex(it)�
	�ENDIF�
	'''
}

def String dropContainedColumnIndex(Reference it) {
	'''�it.to.attributes.filter(a | a.index == true).map[a | dropIndex(a, getDatabaseName(it) + "_", from)].join�'''
}

def String dropIndex(Attribute it, String prefix, DomainObject domainObject) {
	var actualDomainObject = if (domainObject.^extends != null && isInheritanceTypeSingleTable(domainObject.getRootExtends())) domainObject.getRootExtends() else domainObject
	'''
	DROP INDEX IX_�truncateLongDatabaseName(actualDomainObject.getDatabaseName(), getDatabaseName(prefix, it))�;
	'''
}

def String dropDiscriminatorIndex(DomainObject it) {
	'''
	DROP INDEX IX_�truncateLongDatabaseName(getDatabaseName(it), inheritance.discriminatorColumnName())�;
	'''
}

}

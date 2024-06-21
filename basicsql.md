---
date: 2024-06-20
type: reference
system: sql
---

This is a basic query in sql which will return all of the items in the specified table.

```sql
Select * from MYTABLENAME
```

This is a basic query in sql which will return the values matching a specific query from the specified table.

```sql
Select * from MYTABLENAME where ColumnName = 'value'
```

This query can be used to find items that include a set of defined values

```sql
Select * from MYTABLE NAME where ColumnName In ('valueA', 'valueB', 'valueC')
```

The reverse can be true used as well.
```sql
Select * from MYTABLE NAME where ColumnName Not In ('valueA', 'valueB', 'valueC')
```

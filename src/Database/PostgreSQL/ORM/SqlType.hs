{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Database.PostgreSQL.ORM.SqlType (SqlType(..), getTypeOid) where

import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import Data.Int
import Data.Monoid
import qualified Data.Text as ST
import qualified Data.Text.Lazy as LT
import Data.Time
import Data.Typeable
import qualified Data.Vector as V
import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.FromField
import Database.PostgreSQL.Simple.Time
import Database.PostgreSQL.Simple.ToField
import Database.PostgreSQL.Simple.TypeInfo.Static
import Database.PostgreSQL.Simple.Types

import Database.PostgreSQL.ORM.Model

newtype ExtractTypeOid = ExtractTypeOid Oid
instance FromField ExtractTypeOid where
  fromField f _ = return $ ExtractTypeOid $ typeOid f

-- | Retreive the 'Oid' corresponding to a type.  You can subsequently
-- use the 'Oid' to call 'getTypeInfo' for more information on the
-- type.
getTypeOid :: Connection -> S.ByteString -> IO Oid
getTypeOid c tname = do
  [Only (ExtractTypeOid ti)] <- query_ c $ Query $ "SELECT NULL :: " <> tname
  return ti

-- | The class of Haskell types that can be converted to and from a
-- particular SQL type.  For most instances, you only need to define
-- 'sqlBaseType'.
class (ToField a, FromField a) => SqlType a where
  sqlBaseType :: a -> S.ByteString
  -- ^ The name of the SQL type corresponding to Haskell type @a@,
  -- when a value of @a@ can be null.  This is the SQL type to and
  -- from which a @'Maybe' a@ will be converted (where 'Nothing'
  -- corresponds to the SQL value null).
  sqlType :: a -> S.ByteString
  -- ^ The name of the SQL type corresponding to Haskell type @a@,
  -- when @a@ is not wrapped in 'Maybe' and hence cannot be null.  If
  -- @sqlType@ is unspecified, the default is to append \"@NOT NULL@\"
  -- to 'sqlBaseType'.
  {-# INLINE sqlType #-}
  sqlType _ = (sqlBaseType (undefined :: a)) <> " NOT NULL"

#define TYPE(hs, sql) \
    instance SqlType (hs) where sqlBaseType _ = typname (sql)
TYPE(Bool, bool)
TYPE(Double, float8)
TYPE(Float, float4)
TYPE(Int16, int2)
TYPE(Int32, int4)
TYPE(Int64, int8)
TYPE(S.ByteString, text)
TYPE(L.ByteString, text)
TYPE(ST.Text, text)
TYPE(LT.Text, text)
TYPE(Oid,oid)
TYPE(LocalTime, timestamp)
TYPE(ZonedTime, timestamptz)
TYPE(TimeOfDay, time)
TYPE(UTCTime, timestamptz)
TYPE(Day, date)
TYPE(Date, date)
TYPE(ZonedTimestamp, timestamptz)
TYPE(UTCTimestamp, timestamptz)
TYPE(LocalTimestamp, timestamp)
TYPE(String, text)
TYPE(Binary S.ByteString, bytea)
TYPE(Binary L.ByteString, bytea)

#undef TYPE

instance SqlType DBKey where
  sqlType _ = "bigserial UNIQUE NOT NULL PRIMARY KEY"
  sqlBaseType _ = error "DBKey should not be wrapped in type"

instance (SqlType a) => SqlType (Maybe a) where
  sqlType _ = sqlBaseType (undefined :: a)
  sqlBaseType _ = error "Table field Maybe should not be wrapped in other type"

instance (Typeable a, SqlType a) => SqlType (V.Vector a) where
  sqlBaseType _ = sqlBaseType (undefined :: a) <> "[]"

instance (Model a) => SqlType (DBRef a) where
  sqlBaseType (DBRef k) = sqlBaseType k <> ref
    where t = modelInfo :: ModelInfo a
          Just orig = modelOrigTable (modelIdentifiers :: ModelIdentifiers a)
          ref = S.concat [
              " REFERENCES ", quoteIdent orig, "("
              , quoteIdent (modelColumns t !! modelPrimaryColumn t), ")" ]

instance (Model a) => SqlType (DBRefUnique a) where
  sqlBaseType (DBRef k) = sqlBaseType k <> ref
    where t = modelInfo :: ModelInfo a
          Just orig = modelOrigTable (modelIdentifiers :: ModelIdentifiers a)
          ref = S.concat [
              " UNIQUE REFERENCES ", quoteIdent orig , "("
              , quoteIdent (modelColumns t !! modelPrimaryColumn t), ")" ]

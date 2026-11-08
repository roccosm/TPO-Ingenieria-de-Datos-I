USE TPOAndreaniGrupo03;
GO

CREATE ROLE rol_Administrador;
CREATE ROLE rol_OperadorDeposito;
CREATE ROLE rol_OperadorLogistico;
CREATE ROLE rol_AtencionCliente;
CREATE ROLE rol_Supervisor;
GO

-- Permisos del operador de deposito
GRANT EXECUTE ON dbo.sp_AsignarLotesPedido
TO rol_OperadorDeposito;

GRANT EXECUTE ON dbo.sp_RegistrarPreparacion
TO rol_OperadorDeposito;

GRANT EXECUTE ON dbo.sp_ValidarPreparacion
TO rol_OperadorDeposito;

GRANT EXECUTE ON dbo.sp_ArmarCajasPedido
TO rol_OperadorDeposito;
GO

-- Permisos del operador logistico
GRANT EXECUTE ON dbo.sp_ArmarEnvioAutomatico
TO rol_OperadorLogistico;

GRANT EXECUTE ON dbo.sp_RegistrarResultadoEntrega
TO rol_OperadorLogistico;
GO

-- Permisos de atencion al cliente
GRANT SELECT ON dbo.fn_DetallePedido
TO rol_AtencionCliente;

GRANT SELECT ON dbo.fn_HistorialEntregasPedido
TO rol_AtencionCliente;
GO

-- Permisos del supervisor

GRANT SELECT ON dbo.vw_KPI_EntregasATiempo
TO rol_Supervisor;

GRANT SELECT ON dbo.vw_KPI_ErroresPreparacion
TO rol_Supervisor;

GRANT SELECT ON dbo.vw_KPI_IntentosEntrega
TO rol_Supervisor;

GRANT EXECUTE ON dbo.sp_ConsultarTrazabilidadLote
TO rol_Supervisor;
GO

-- Permisos del administrador
GRANT CONTROL ON DATABASE::TPOAndreaniGrupo04
TO rol_Administrador;
GO

-- Crear usuarios de prueba
CREATE USER usr_Deposito WITHOUT LOGIN;
CREATE USER usr_Logistica WITHOUT LOGIN;
CREATE USER usr_AtencionCliente WITHOUT LOGIN;
CREATE USER usr_Supervisor WITHOUT LOGIN;
GO

-- Asignar roles a los usuarios de prueba
ALTER ROLE rol_OperadorDeposito
ADD MEMBER usr_Deposito;

ALTER ROLE rol_OperadorLogistico
ADD MEMBER usr_Logistica;

ALTER ROLE rol_AtencionCliente
ADD MEMBER usr_AtencionCliente;

ALTER ROLE rol_Supervisor
ADD MEMBER usr_Supervisor;
GO
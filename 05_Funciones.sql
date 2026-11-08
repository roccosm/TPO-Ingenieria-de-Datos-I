USE TPOAndreaniGrupo03;
GO

CREATE FUNCTION fn_DetallePedido
(
    @IdPedido INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        IdMedicamento,
        CantidadSolicitada
    FROM DETALLE_PEDIDO
    WHERE IdPedido = @IdPedido
);
GO


CREATE FUNCTION fn_HistorialEntregasPedido
(
    @IdPedido INT
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        IdEnvio,
        FechaPrevista,
        FechaIntento,
        Estado,
        Resultado
    FROM PEDIDO_ENVIO
    WHERE IdPedido = @IdPedido
);
GO

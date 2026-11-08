USE TPOAndreaniGrupo03
GO

CREATE TRIGGER tr_ControlarCapacidadCaja
ON DETALLE_CAJA
AFTER INSERT, UPDATE
AS
BEGIN
    IF EXISTS (
        SELECT 1
        FROM DETALLE_CAJA DC
        WHERE DC.IdCaja IN (
            SELECT IdCaja
            FROM INSERTED
        )
        GROUP BY DC.IdCaja
        HAVING SUM(DC.CantidadEmpacada) > 10
    )
    BEGIN
        PRINT 'La caja supera el limite de 10 unidades.';
        ROLLBACK TRANSACTION;
        RETURN;
    END;
END;
GO
